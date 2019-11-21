#!/bin/zsh

# Simple static pictures gallery generator
#  https://github.com/calandoa/genpict
#
# Antoine Calando (wacalando@wfree.wfr s/w//g)
#
# This code is public domain.
#
# version 0.1 - sept 2017
#

# #################################################################################################################
# Genpict const

# W/H of images and videos
WIDTH_MAX=1536
HEIGHT_MAX=1024
COL_CNT=8

# Extensions recognized
IMG_EXT=(jpg jpeg png gif)
VID_EXT=(mp4)

# Bad qualities to get smaller files. Video is Constant Rate Factor and FFmpeg preset.
JPEG_QUALITY=80
VIDEO_QUALITY=(30 slower)

# Text and background colors
typeset -A COLORS
COLORS=( white "color:#000000; background-color:#FFFFFF;" \
	lgrey  "color:#CCCCCC; background-color:#666666;" \
	grey   "color:#CCCCCC; background-color:#444444;" \
	dgrey  "color:#CCCCCC; background-color:#222222;" \
	black  "color:#FFFFFF; background-color:#000000;" )

# Simultaneous job count
JOBS_MAX=$(nproc)

TOP_FORMAT=(40px 25px)
LEFT_FORMAT=(70px 50px 60% auto)
TEXT_FONT="bold 50px/100px Arial"
TEXT_BG="rgba(0,0,0,.7)"


# #################################################################################################################
# Generic const and setup
setopt extendedglob
ESC_CHAR=$(printf '\033')
ANSI_RED=$ESC_CHAR'[31m'
ANSI_CYAN=$ESC_CHAR'[36m'
ANSI_OFF=$ESC_CHAR'[0m'

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

# Parse options here to declare default arguments
zparseopts -D -K t:=title T:=subtitle s:=side f:=format o:=outdir c:=color 1:=first d=dbg r=remove n=nonrec i=index  h=help

# Default arguments
title=${title[2]-"My Photos"}
subtitle=${subtitle[2]-"My not so short subtitle"}
outdir=${outdir[2]-html}
color=${color[2]-grey}
side=${side[2]-left}
first=${first[2]-}
case $side in
 (none) 	;;
 (top) 		format=( ${=format[2]-$TOP_FORMAT} ) ;;
 (left|right) 	format=( ${=format[2]-$LEFT_FORMAT} ) ;;
 (*) 		error "Unkown title type: $side";;
esac


# help ?
[[ -n $help ]] && {
	print "Usage: genpict.zsh [options] [input folders]\n"	\
		"\n" \
		"Simple static pictures gallery generator.\n" \
		"\n" \
		"	-t title 	: title \n" \
		"	-T subtitle	: subtitle \n" \
		"	-s side		: title side (none,top,left,right)\n" \
		"	-f \"format\"	: title format (\"size_t size_T pos_Y pos_X\")\n" \
		"	-c color	: color (white, grey, black)\n" \
		"	-o out		: output folder (def: html)\n" \
		"	-d 		: debug (quick pass without copy or conversion)\n" \
		"	-r		: remove existing output folder if any \n" \
		"	-n		: non-recursive scanning \n" \
		"	-1 substr	: use picture containing substr as first one \n" \
		"	-i		: generate index \n" \
		"	\n" \
		"Title and subtitles are on the left side by default, overlaid over the first image.\n" \
		"other arguments are none (no title), top (centered over the image), right (overlaid on the right).\n" \
		"\n" \
		"Default format is \"$LEFT_FORMAT\": 1st and 2nd arguments are title and subtitle font size,\n" \
		"3rd and 4th are used with left/right titles and are the vertical and horizontal position.\n" \
		"These arguments use standard browser units: px, %, auto...\n" \
		"\n" \
		"Subtitle can be removed by setting it to \"\".\n" \
		"\n" \

	exit 1 }


# Basic checks
[[ -z $COLORS[$color] ]] && error "Unkown color \"$color\""
[[ $side != none && $side != top && $side != left && $side != right ]] && error "Unkown title type \"$side\""
(( $+commands[ffmpeg] && $+commands[ffprobe] )) || error "Cannot find ffmpeg/ffprobe"
(( $+commands[convert] && $+commands[identify] )) || error "Cannot find Image Magick convert/identify"
(( $+commands[exiftool] )) || error "Cannot find exiftool"
(( $+commands[jpegtran] )) || error "Cannot find jpegtran"	# ubuntu 16.04 pkg: libjpeg-progs

# Remaining opt are dirs, use . if none
indir=( ${*:-.} )

print "Title:    " $ANSI_CYAN$title	$ANSI_OFF
print "Subtitle: " $ANSI_CYAN$subtitle	$ANSI_OFF
print "Side:     " $ANSI_CYAN$side	$ANSI_OFF
print "Format:   " $ANSI_CYAN$format	$ANSI_OFF
print "Color:    " $ANSI_CYAN$color	$ANSI_OFF
print "In dir(s):" $ANSI_CYAN$indir	$ANSI_OFF
print "Out dir:  " $ANSI_CYAN$outdir	$ANSI_OFF
print

# Get all the subfolders
indir_rec=( ${^indir}(/N) )
[[ -z $nonrec ]] &&  indir_rec+=( ${^indir}/**/*~**/$outdir/**~**/$outdir(/N) )
[[ -z "$indir_rec" ]] && error "No directory found"

# Scan recursively images and videos and remember paths
print "Scanning folders..."
media=()
for f in ${^indir_rec}/*(.,@) ; do
	ext="$f:e:l"
	(( $+IMG_EXT[(r)$ext] || $+VID_EXT[(r)$ext] )) && media+=("$f")
done
[[ -z $media ]] && error "No image or video found"

# Create output dir
if [[ -z $dbg ]] ; then
	[[ -n $remove ]] && rm -fR $outdir
	[[ -d $outdir ]] && error "Remove existing $outdir"
	mkdir -p $outdir
elif [[ ! -d $outdir ]] ; then
	print "No $outdir folder, canceling debug mode"
	dbg=''
fi

# Get first picture
[[ -n $first ]] && { first=$media[(r)*$first*]; [[ -z $first ]] && error "First image not found" }

type=()

print "Processing images..."
# main loop to process all images
for f in $media ; do
	ext="$f:e:l"
	if (( $+IMG_EXT[(r)$ext] )); then

		print "  Processing image $f"

		# # Get WxH with IM
		size=( $( identify -format '%w %h %[EXIF:Orientation]' "$f" 2>/dev/null) )
		# Exiftool much quicker than IM
		#orient=$(exiftool -p '$Orientation#' "$f" 2>/dev/null)

		# Orientation code (left: rotated, right: +mirrored)
		# 0 Undefined
		# 1 Top-Left		2 Top-Right
		# 3 Bottom-Right	4 Bottom-Left
		# 6 Right-Top		5 Left-Top
		# 8 Left-Bottom		7 Right-Bottom
		orient=$size[3]
		(( orient == 6 || orient == 8 )) && size=( $size[2] $size[1] )
		(( w = size[1], h = size[2] ))
		# Compute size so img fit into the screen, without increasing its size
		(( ratio_w = $w.0 / WIDTH_MAX ))
		(( ratio_h = $h.0 / HEIGHT_MAX ))
		(( ratio = ratio_w > ratio_h? ratio_w : ratio_h))
		(( ratio = ratio > 1 ? ratio : 1 ))
		# The "| 0" allows to truncate the float to an int
		(( width_n = (w / ratio) | 0 ))
		(( height_n = (h / ratio) | 0 ))

		# type is 0:landscape, 1:portrait, 2:panorama; last 2 will get 2 cells for index
		(( t = (width_n < height_n) + 2*( 2 * height_n < width_n) )) && CS=1.93 || CS=1
		type+=( $t )
		(( width_i = (width_n * CS / (COL_CNT + 2)) | 0 ))
		(( height_i = (height_n * CS / (COL_CNT + 2)) | 0 ))

		if [[ -z $dbg ]] ; then

			[[ $f:e:l == jpe#g ]] && jpgqual=(-quality $JPEG_QUALITY) || jpgqual=""

			# create smaller picture and optimize it
			dest_sm="${$f:t:r}_sm.jpg"
			para "convert -auto-orient \"$f\" $jpgqual -resize ${width_n}x${height_n} \"$outdir/${dest_sm}.tmp\" ;\
				jpegtran -copy none -optimize -progressive -outfile \"$outdir/$dest_sm\" \"$outdir/${dest_sm}.tmp\" "

			# Same for index
			dest_i="${$f:t:r}_i.jpg"
			[[ -n $index ]] && para "convert -auto-orient \"$f\" $jpgqual -resize ${width_i}x${height_i} \"$outdir/${dest_i}.tmp\" ;\
				jpegtran -copy none -optimize -progressive -outfile \"$outdir/$dest_i\" \"$outdir/${dest_i}.tmp\" "

			# add an optimized copy of the original image
			para "jpegtran -copy all -optimize -progressive -outfile \"$outdir/$dest\" \"$f\" "
		fi

	elif (( $+VID_EXT[(r)$ext] )); then

		print "  Processing video $f"
		dest="${f:t:r}.mp4"
		dest_sm="${dest:r}_sm.jpg"

		# Retrieve w/h/r, expected output:
		#    width=XXX
		#    height=YYY
		#    [rotation=-90|90|180|270]
		hw_raw=$( ffprobe -v quiet -print_format ini -show_streams -i "$f" | grep '^\(height\|width\|rotate\)=' )
		[[ $hw_raw == width=[0-9]##?height=[0-9]##(?rotate=[0-9]##)# ]] || error "Unexpected h/w/r output for video $f: <$hw_raw>"
		rotate=0
		eval $hw_raw

		[[ $rotate == -90 || $rotate == 90 || $rotate == 270 ]] && { tmp=$width ; width=$height ; height=$tmp }
		(( ratio_w = $width.0 / WIDTH_MAX ))
		(( ratio_h = $height.0 / HEIGHT_MAX ))
		(( ratio = ratio_w > ratio_h? ratio_w : ratio_h))
		(( ratio = ratio > 1 ? ratio : 1 ))
		# Make sure w&h are multiples of 2, and round them to int
		(( width_n = ($width / ratio + 1) & 65534 ))
		(( height_n = ($height / ratio + 1) & 65534 ))
		type+=( $t )

		if [[ -z $dbg ]] ; then

			# extract first frame for poster image
			ffmpeg -v quiet  -i "$f" -qscale:v 10 -vframes 1 -s ${width_n}x${height_n} -f singlejpeg "$outdir/${dest_sm}.tmp"

			# draw an ugly green triangle simulating a play button
			((trl = (width_n*2/3 < 100)? width_n*2/3 : 100 ))
			((trl = (height_n*2/3 < trl)? height_n*2/3 : trl ))
			((tr_xl = width_n/2 - trl))
			((tr_xr = width_n/2 + trl))
			((tr_yc = height_n/2))
			((tr_yt = tr_yc - trl))
			((tr_yb = tr_yc + trl))
			convert "$outdir/${dest_sm}.tmp" -quality 95 -fill green3 -stroke black -draw "path \"M $tr_xl,$tr_yt L $tr_xr,$tr_yc L $tr_xl,$tr_yb Z\" " "$outdir/$dest_sm"

			# reduce video size and quality
			para "log=\$(ffmpeg -i \"$f\" -s ${width_n}x${height_n} -vcodec libx264 -crf $VIDEO_QUALITY[1] -preset $VIDEO_QUALITY[2] -strict -2 \"$outdir/$dest\" 2>&1 ) ; \
				(( \$? )) && error \"Error while processing $f with ffmpeg:$OFF\n\n\$log\" "
		fi
	fi
	# Close div overlay after the first image only
	((cnt++ == 0 )) && [[ -z $first ]] && print "</div>" >> $outdir/index.html
done

print "Generating HTML..."
# create HTML file with style and some JS to scroll to images with space/shift+space
# console.log();
# console.log("C" + cnt + "  P " + window.pageYOffset + "  eoT " + el.offsetTop + "  wiH " + window.innerHeight + "  eoH " + el.offsetHeight + "  e " + (el.offsetTop - (window.innerHeight - el.offsetHeight) / 2) + "  sk " +  !ev.shiftKey);
# console.log("  diff: " + Math.abs(goy - posy) + " | pyo " + posy + " g " + goy + " | w " + window.innerHeight + " oh " +  document.body.offsetHeight);
# console.log("s1: " + step);
# console.log("s2: " + (goy - posy) + ":" + window.pageYOffset);
cat << EOF > $outdir/index.html
<!DOCTYPE html>
<html>

<head>
	<meta charset="utf-8">
	<script type="text/javascript">
		addEventListener("keypress", function (ev) {
			if (ev.keyCode === 0 || ev.keyCode === 32) {
				ev.preventDefault()
				var ely_p = 0;
				for (var cnt = 0; el = document.getElementById("media" + cnt) ; cnt++) {
					var ely = el.offsetTop - (window.innerHeight - el.offsetHeight) / 2;
					if (window.pageYOffset <= ely + (ev.shiftKey? 1 : -2)) {
						var goy = ev.shiftKey? ely_p : ely;
						var step = ev.shiftKey? -150 : 150;
						var posy_p = NaN;
						var scrollInterval = setInterval( function() {
							var posy =  Math.round(window.pageYOffset);
							if (posy_p == posy)
								clearInterval(scrollInterval);
							else if (Math.abs(goy - posy) > 150)
								window.scrollBy( 0, step);
							else
								window.scrollBy( 0, goy - posy + (ev.shiftKey? -0.5 : 0.5));
							posy_p = posy;
						}, 20);
						break;
					}
					ely_p = ely;
				}
			}
		});
	</script>
	<title>$title</title>
	<style>
	body	   { margin: auto;
		     width: ${WIDTH_MAX}px;
		     $COLORS[$color] }
	.ctr 	   { text-align: center; }
	.footer    { text-align: right; }

EOF

# Fill CSS depending on title type
if [[ $side == top ]]; then
	cat <<- EOF >> $outdir/index.html
	 	.title { text-align: center; }
	 	.span1 { font-size: $format[1]; }
	 	.span2 { font-size: $format[2]; }
	EOF

elif [[ $side == left || $side == right ]]; then
	[[ $side == right && $format[4] == auto ]] && format[4]="0px"


	cat <<- EOF >> $outdir/index.html
	 	div { position: relative; }
	 	.title { text-align: $side;
	 		position: absolute;
	 		top: $format[3];
	 		$side: $format[4]; }
	 	span { background: $TEXT_BG;
	 		font: $TEXT_FONT;
	 		padding:10px; }
	 	.span1 { font-size: $format[1]; }
	 	.span2 { font-size: $format[2]; }
	EOF
elif [[ $side == none ]]; then
	cat <<- EOF >> $outdir/index.html
		.title { display: none; }
	EOF
fi

# Line break and span only if subtitle exists
[[ -n $subtitle ]] && span_subtitle="<br><span class=\"span2\">&thinsp;$subtitle</span><br>"

# Close style/head and output title and subtitle
cat << EOF >> $outdir/index.html
	</style>
</head>
<body>
	<div>
		<p class="title">
			<span class="span1">&thinsp;$title</span>
			$span_subtitle
		</p>
EOF

if [[ -n $first ]]; then
	print "  Including first image $first"
	dest="$first:t"
	print  "		<p class="ctr"><a href=\"$dest\"><img src=\"${dest:r}_sm.jpg\" alt=\"$dest\"></a></p><br>" >> $outdir/index.html

	# close title div
	cat <<- EOF >> $outdir/index.html
	 	</div>
	 	<p class="ctr" style="color:#666666">Space (or Shift+space) to scroll</p><br>
	EOF
fi


if [[ -n $index ]]; then
	print "  Generating index 1st pass"

	# First pass to reorder images, to avoid empty or overlaping cells because of portrait/pano
	# Landscape thumbnails take one cell, portrait are 2 cells high and panorama 2 wide
	# i: img idx, j: cell idx
	(( i=1, j=1))
	# indirect array for reordering
	reord=( {1..$#media} )
	# generate array of 0, 4 * media cnt to be sure; 1 will mark overlapping portrait on bottom cell
	rowspan=( ${$(seq $(( 4 * $#media )) )/*/0} )

	while true; do
		# new row?
		if (( j % COL_CNT == 1 )) ; then
			# bad and last br used to avoid portrait in last row
			bad=()
			lastbr=$i
		fi
		# cell overlapped by portrait above?
		(( rowspan[j] && j++ )) && continue

		if (( type[reord[i]] == 2 )) ; then
			# pano; ++j below because additional cell is used
			if (( ++j % COL_CNT == 1 || rowspan[j] )) ; then
				# next cell not available, so swap with next non pano
				for (( k =i ; type[reord[k]] == 2 ; k++ )) do done
				if (( k <= $#media )) ; then
					# swap found, current pano will be re-processed
					tmp=$reord[i] ; reord[i]=$reord[k] ; reord[k]=$tmp
					(( j--))
				fi
				continue
			fi

		elif (( type[reord[i]] == 1 )) ; then
			# portrait
			rowspan[j+COL_CNT]=1
			bad+=( $reord[i] )
		fi

		(( j++, $#media < ++i)) && break
	done

	# if portrait on last row and enough landscape img, then reorder them
	if (( $#bad && 2 * $#bad <= $#reord )); then
		# landscape img to swap are the last before last line
		# (bug here? use $bad for all portraits and $lastbad for last line only?)
		good=( ${${reord[1,lastbr-1]:|bad}[-$#bad,-1]} )
		# take all img before last line and without those to swap, add the portrait,
		# add the swapped, and add the remaining from last line
		reord=( ${reord[1,lastbr-1]:|good} $bad $good ${reord[lastbr,-1]:|bad} )
	fi

	print "  Generating index 2nd pass"
	cat <<- EOF >> $outdir/index.html
	 	<table id="media0" style="margin:auto"><tr>
	EOF

	(( i=1,  col_next = COL_CNT, br_curr = i + col_next))
	while true; do
		if (( i == br_curr )) ; then
			print  "	</tr><tr>" >> $outdir/index.html
			(( br_curr = i + col_next, col_next = COL_CNT))
		fi

		j=$reord[i]
		span=''
		if (( type[j] == 1 )) ; then
			(( col_next-- ))
			span=' rowspan="2"'

		elif (( type[j] == 2 )) ; then
			(( --br_curr == i )) && continue
			span=' colspan="2"'
		fi

		dest="${media[j]:t:r}_i.jpg"
		cat <<- EOF >> $outdir/index.html
		 		<th$span><a href="#media$j"><img src="$dest" alt="$dest"></a></th>
		EOF

		(($#media < ++i)) && break
	done

	cat <<- EOF >> $outdir/index.html
	 	</tr></table>
	EOF
else
	cat <<- EOF >> $outdir/index.html
	 	<div id='media0'></div>
	EOF
fi

cnt=1

# main loop to process all images
for f in $media ; do
	ext="$f:e:l"
	if (( $+IMG_EXT[(r)$ext] )); then

		print "  Including image $f"
		dest="$f:t"
		dest_sm="${dest:r}_sm.jpg"


		# add HTML tags
		cat <<- EOF >> $outdir/index.html
		 	<p class="ctr"><a href="$dest"><img src="$dest_sm" alt="$dest" id="media$cnt"></a></p><br>
		EOF

	elif (( $+VID_EXT[(r)$ext] )); then

		print "  Processing video $f"
		dest="${f:t:r}.mp4"
		dest_sm="${dest:r}_sm.jpg"

		cat <<- EOF >> $outdir/index.html
		 	<p class="ctr"><video poster="$dest_sm" onclick="this.paused?this.play():this.pause();" id="media$cnt">
		 		<source src="$dest" type="video/mp4" />
		 	</video></p><br>
		EOF
	fi
	# Close div overlay after the first image only and if no first img
	((cnt++ == 1 )) && [[ -z $first ]] && print "</div>" >> $outdir/index.html
done

# add footer. id is added on purpose to scroll up to this footer
cat << EOF >> $outdir/index.html

	<p class='footer' id='media$cnt'> Generated $(date) by <a href="https://github.com/calandoa/genpict">genpict</a><br>Click on pictures for full size file</p>

</body>
</html>
EOF

print "Done, waiting for last jobs..."

# wait for all jobs to finish
wait
[[ -n $outdir/*.tmp(#qN) ]] && rm -f $outdir/*.tmp
