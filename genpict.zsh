#!/bin/zsh

# Generic const and setup
setopt extendedglob
ESC_CHAR=$(printf '\033')
ANSI_RED=$ESC_CHAR'[31m'
ANSI_CYAN=$ESC_CHAR'[36m'
ANSI_OFF=$ESC_CHAR'[0m'

# Genpict const
WIDTH_MAX=1536.00
HEIGHT_MAX=1024.00
JOBS_MAX=4
IMG_EXT=(jpg jpeg png gif)
VID_EXT=(mp4)
JPG_QUALITY=80

typeset -A THEMES
THEMES=( white "color:#000000; background-color:#FFFFFF;" \
	grey  "color:#CCCCCC; background-color:#222222;" \
	black "color:#FFFFFF; background-color:#000000;" )

# Parse options here to declare default arguments
zparseopts -D -K t:=title s:=subtitle o:=outdir m:=theme d=dbg f=force h=help

# Default arguments
title=${title[2]:-"My Photos"}
subtitle=${subtitle[2]:-"My not so short subtitle"}
outdir=${outdir[2]:-html}
theme=${theme[2]:-white}

# Generic functions
error() {
    if [[ $1 != '' ]] print $ANSI_RED"\n*** ERROR: "$1"\n"$ANSI_OFF 1>&2
    exit 1
}

para() {
	lock=/tmp/para_$$_$((paracnt++))
	# sleep until the 4th lock file is no more (#q for globbing in test, [4] for 4th, N to avoid error if none)
	until [[ -z /tmp/para_$$_*(#q[JOBS_MAX]N) ]] { sleep 0.1 }
	# Launch the job in a subshell
	( touch $lock ; eval $* ; rm $lock ) &
	# Wait for subshell start and lock creation
	until [[ -f $lock ]] { sleep 0.001 }
}


# #################################################################################################################
# Genpict script

# help ?
[[ -n $help ]] && { print "Usage: genpict.zsh -x -y -z" ; exit 1 }


[[ -z $THEMES[$theme] ]] && error "Unkown theme \"$theme\""

# Remaining opt are dirs, use . if none
indir=( ${*:-.} )

print "Title:    " $ANSI_CYAN$title	$ANSI_OFF
print "Subtitle: " $ANSI_CYAN$subtitle	$ANSI_OFF
print "In dir(s):" $ANSI_CYAN$indir	$ANSI_OFF
print "Out dir:  " $ANSI_CYAN$outdir	$ANSI_OFF
print "Theme:    " $ANSI_CYAN$theme	$ANSI_OFF
print

# Get all the subfolders
indir_rec=( ${^indir}(/N) ${^indir}/**/*~**/$outdir/**~**/$outdir(/N) )
[[ -z "$indir_rec" ]] && error "No directory found"

# Get all the images and videos
media=()
for f in ${^indir_rec}/*(.) ; do
	ext="$f:e:l"
	[[ -n $IMG_EXT[(r)$ext] || -n $VID_EXT[(r)$ext] ]] && media+=("$f")
done
[[ -z $media ]] && error "No image or video found"

# Create output dir
[[ -n $force ]] && rm -fR $outdir
[[ -d $outdir ]] && error "Remove existing $outdir"
mkdir $outdir

# console.log('Space pressed ' + document.documentElement.scrollTop + ' ' + window.scrollY);

cat << EOF > $outdir/index.html
<!DOCTYPE html>
<html>

<head>
	<meta charset="utf-8">

	<style>
	html	   { text-align: center;
		     margin: auto;
		     width: 1536px; }
	img, video { margin:12px ; }
	body	   { $THEMES[$theme] }
	</style>

	<script type="text/javascript">
		addEventListener("keypress", function (ev) {
			if (ev.keyCode === 0 || ev.keyCode === 32) {
				ev.preventDefault()

				var posy = window.scrollY;
				var ely_p = 0;
				for (var cnt = 0; el = document.getElementById("media" + cnt) ; cnt++) {
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
	<title>$title</title>
</head>


<body>

<h1>$title</h1>
<h2>$subtitle</h2>

EOF

cnt=0
for f in $media ; do
	ext="$f:e:l"
	if [[ -n $IMG_EXT[(r)$ext] ]]; then

		print "Processing image $f..."
		dest="$f:t"
		dest_sm="${dest:r}_sm.jpg"

		# Get WxH with IM
		size=( $( identify -format "%w %h" "$f") )
		# Exiftool much quicker than IM
		orient=$(exiftool -p '$Orientation#' "$f" 2>/dev/null)
		# Orientation code (left: rotated, right: +mirrored)
		# 0 Undefined
		# 1 Top-Left		2 Top-Right
		# 3 Bottom-Right	4 Bottom-Left
		# 6 Right-Top		5 Left-Top
		# 8 Left-Bottom		7 Right-Bottom
		(( orient == 6 || orient == 8 )) && size=( $size[2] $size[1] )
		(( ratio_w = $size[1] / $WIDTH_MAX ))
		(( ratio_h = $size[2] / $HEIGHT_MAX ))
		(( ratio = ratio_w > ratio_h? ratio_w : ratio_h))
		(( ratio = ratio > 1 ? ratio : 1 ))
		# The "| 0" allows to truncate the float to an int
		(( width_n = ($size[1] / ratio) | 0 ))
		(( height_n = ($size[2] / ratio) | 0 ))

		if [[ -z $dbg ]] ; then


			[[ $f:e:l == jpe#g ]] && jpgqual=(-quality $JPG_QUALITY)

			para "convert -auto-orient \"$f\" $jpgqual -resize ${width_n}x${height_n} \"$outdir/${dest_sm}.tmp\" ;\
				jpegtran -copy none -optimize -progressive -outfile \"$outdir/$dest_sm\" \"$outdir/${dest_sm}.tmp\" "
			para "jpegtran -copy all -optimize -progressive -outfile \"$outdir/$dest\" \"$f\" "

			cat <<- EOF >> $outdir/index.html

			<a href="$dest"><img src="$dest_sm" alt="$dest" id="media$cnt"></a><br>
			EOF

		else
			#dbg: only file links and no resizing

			ln -s "$f" "$outdir/$f:t"

			cat <<- EOF >> $outdir/index.html

			<a href="$f:t"><img src="$f:t" alt="$f:t" width="$width_n" height="$height_n" id="media$cnt"></a><br>
			EOF

		fi
	elif [[ -n $VID_EXT[(r)$ext] ]]; then

		print "Processing video $f..."

		# Retrieve w/h/r, expected output:
		#    width=XXX
		#    height=YYY
		#    [rotation=-90|90|180|270]

		hw_raw=$( ffprobe -v quiet -print_format ini -show_streams -i "$f" | grep '^\(height\|width\|rotate\)=' )
		[[ $hw_raw == width=[0-9]##?height=[0-9]##(?rotate=[0-9]##)# ]] || error "Unexpected h/w/r output for video $f: <$hw_raw>"
		rotate=0
		eval $hw_raw

		[[ $rotate == -90 || $rotate == 90 || $rotate == 270 ]] && { tmp=$width ; width=$height ; height=$tmp }
		(( ratio_w = $width / $WIDTH_MAX ))
		(( ratio_h = $height / $HEIGHT_MAX ))
		(( ratio = ratio_w > ratio_h? ratio_w : ratio_h))
		(( ratio = ratio > 1 ? ratio : 1 ))
		# Make sure w&h are multiples of 2
		(( width_n = ($width / ratio + 1) & 65534 ))
		(( height_n = ($height / ratio + 1) & 65534 ))

		dest="${f:t:r}.mp4"
		dest_sm="${dest:r}_sm.jpg"

		ffmpeg -v quiet  -i "$f" -qscale:v 10 -vframes 1 -s ${width_n}x${height_n} -f singlejpeg "$outdir/${dest_sm}.tmp"

		((trl = (width_n*2/3 < 100)? width_n*2/3 : 100 ))
		((trl = (height_n*2/3 < trl)? height_n*2/3 : trl ))
		((tr_xl = width_n/2 - trl))
		((tr_xr = width_n/2 + trl))
		((tr_yc = height_n/2))
		((tr_yt = tr_yc - trl))
		((tr_yb = tr_yc + trl))

		convert "$outdir/${dest_sm}.tmp" -quality 95 -fill green3 -stroke black -draw "path \"M $tr_xl,$tr_yt L $tr_xr,$tr_yc L $tr_xl,$tr_yb Z\" " "$outdir/$dest_sm"

		para "log=\$(ffmpeg -i \"$f\" -s ${width_n}x${height_n} -vcodec libx264 -crf 30 -preset slower -strict -2 \"$outdir/$dest\" 2>&1 ) ; \
			(( \$? )) && error \"Error while processing $f with ffmpeg:$OFF\n\n\$log\" "

		cat <<- EOF >> $outdir/index.html

		<video poster="$dest_sm" onclick="this.paused?this.play():this.pause();" id="media$cnt">
			<source src="$dest" type="video/mp4" />
		</video><br>
		EOF
	fi
	((cnt++))
done




cat << EOF >> $outdir/index.html

<p align='right'>Generated $(date) by genpict</p>

</body>
</html>
EOF


wait
rm -f "$outdir/*.tmp"

