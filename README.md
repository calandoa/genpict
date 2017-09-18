# genpict
Simple static pictures gallery generator.

This script processes collection of images and generates HTML pages to display these images in one column.

# Features
 - very simple
 - encode images and videos at 1536x1024 and medium quality for smaller files
 - encoded images point to original ones
 - space or shift+space to scroll up and down
 - processing done in parallel jobs

# Dependencies
 - zsh
 - ffmpeg
 - Image Magick
 - exiftool
 - jpegtran

On Ubuntu 16.04:
```
    apt-get install zsh ffmpeg imagemagick exiftool libjpeg-progs
```

# Usage

        genpict.zsh [options] [input folders]

		    -t title 	: title
    		-s subtitle	: subtitle
    		-m theme	: theme (white, grey, black)
    		-o out		: output folder (def: html)
    		-d 		    : debug (quick pass without copy and convertion)
    		-f		    : remove existing output folder if any
