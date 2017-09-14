#!/bin/zsh

setopt extendedglob
ESC_CHAR=$(printf '\033')
ANSI_RED=$ESC_CHAR'[31m'
ANSI_OFF=$ESC_CHAR'[0m'

WIDTH_MAX=1536.00
HEIGHT_MAX=1024.00

error() {
    if [[ $1 != '' ]] print $ANSI_RED"\n*** ERROR: "$1"\n"$ANSI_OFF 1>&2
    exit 1
}

para() {
	lock=/tmp/para_$$_$((paracnt++))
	# sleep until the 4th lock file is no more (#q for globbing in test, [4] for 4th, N to avoid error if none)
	until [[ -z /tmp/para_$$_*(#q[4]N) ]] { sleep 0.1 }
	# Launch the job in a subshell
	( touch $lock ; eval $* ; rm $lock ) &
	# Wait for subshell start and lock creation
	until [[ -f $lock ]] { sleep 0.001 }
}

ALLIMG=(jpg jpeg png gif)


zparseopts -D -K t:=title s:=subtitle o:=outdir h=help d=dbg

title=${title[2]:-"My Photos"}
subtitle=${subtitle[2]:-"My not so short subtitle"}
outdir=${outdir[2]:-html}

[[ -n $help ]] && { print "Usage: genpict.zsh -x -y -z" ; exit 1 }

# Remaining opt are dirs, use . if none
indir=( ${*:-.} )

print "t " $title
print "st" $subtitle
print "o " $outdir
print "a " $indir

indir_rec=( ${^indir}(/N) ${^indir}/**/*~**/$outdir/**~**/$outdir(/N) )

[[ -z "$indir_rec" ]] && error "No directory found"

pict=()

for f in ${^indir_rec}/*(.) ; do
	ext=$f:e:l
	[[ -n $ALLIMG[(r)$ext] ]] && pict+=($f)
done

[[ -z $pict ]] && error "No images found"

#DBG=====================
rm -fR $outdir
[[ -d $outdir ]] && error "Remove existing $outdir"

mkdir $outdir

# console.log('Space pressed ' + document.documentElement.scrollTop + ' ' + window.scrollY);

cat << EOF > $outdir/index.html
<!DOCTYPE html>
<html>


<head>
	<meta charset="utf-8">

	<style>
	html	{ text-align: center;
		  margin: auto;
		  width: 1536px; }
	img	{ margin:12px ; }
	</style>

	<script type="text/javascript">
		addEventListener("keypress", function (ev) {
			if (ev.keyCode === 0 || ev.keyCode === 32) {
				ev.preventDefault()

				var posy = window.scrollY;
				var ely_p = 0;
				for (var cnt = 0; el = document.getElementById("img" + cnt) ; cnt++) {
					var ely = Math.round(el.offsetTop - (window.innerHeight - el.offsetHeight) / 2);
					if (posy <= ely - !ev.shiftKey) {
						var goy = ev.shiftKey? ely_p : ely;
						var step = ev.shiftKey? -100 : 100;
						var scrollInterval = setInterval( function() {
							if ( window.scrollY == goy)
								clearInterval(scrollInterval);
							else if (Math.abs(goy - window.scrollY) > 100)
								window.scrollBy( 0, step);
							else
								window.scrollBy( 0, goy - window.scrollY);
						}, 20);
						break;
					}
					ely_p = ely;
				}
			}
		});
	</script>
</head>

<title>$title</title>

<body>

<h1>$title</h1>
<h2>$subtitle</h2>

EOF


# 0 Undefined
# 1 Top-Left
# 3 Bottom-Right
# 6 Right-Top
# 8 Left-Bottom

# 2 Top-Right
# 4 Bottom-Left
# 5 Left-Top
# 7 Right-Bottom

cnt=0
for f in $pict ; do
	# Get WxH with IM
	size=( $( identify -format "%w %h" "$f") )
	# Exiftool much quicker than IM
	orient=$(exiftool -p '$Orientation#' "$f" 2>/dev/null)

	(( orient == 6 || orient == 8 )) && size=( $size[2] $size[1] )
	(( ratio_w = $size[1] / $WIDTH_MAX ))
	(( ratio_h = $size[2] / $HEIGHT_MAX ))
	(( ratio = ratio_w > ratio_h? ratio_w : ratio_h))
	(( ratio = ratio > 1 ? ratio : 1 ))
	(( width = ($size[1] / ratio) | 0 ))
	(( height = ($size[2] / ratio) | 0 ))

	if [[ -z $dbg ]] ; then

		dest="$f:t"
		dest_sm="${dest:r}_sm.jpg"

		[[ $f:e:l == jpe#g ]] && jpgqual=(-quality 85)

		print "Processing $f...	"
		para "convert -auto-orient \"$f\" $jpgqual -resize ${width}x${height} \"$outdir/${dest_sm}.tmp\" ;\
			jpegtran -copy none -optimize -progressive -outfile \"$outdir/$dest_sm\" \"$outdir/${dest_sm}.tmp\" "
		para "jpegtran -copy all -optimize -progressive -outfile \"$outdir/$dest\" \"$f\" "

		cat <<- EOF >> $outdir/index.html

		<a href="$dest"><img src="$dest_sm" alt="$dest" id="img$cnt"></a>
		EOF

	else
		#dbg: only link to files and no resizing

		ln -s "$f" "$outdir/$f:t"

		cat <<- EOF >> $outdir/index.html
		<a href="$f:t">
		<img src="$f:t" alt="$f:t" width="$width" height="$height" id="img$cnt">
		</a>
		<br>
		EOF

	fi
	((cnt++))
done


cat << EOF >> $outdir/index.html

</body>
</html>
EOF


wait
rm -f "$outdir/*.tmp"

