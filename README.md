# genpict
Simple static pictures gallery generator.

This script processes collection of images and generates HTML pages to display these images in one column.

It was inspired by https://github.com/Jack000/Expose.

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

            -t title    : title
            -T subtitle : subtitle
            -s side     : title side (none,top,left,right)
            -f "format" : title format ("size_t size_T pos_Y pos_X")
            -c color    : color (white, grey, black)
            -o out      : output folder (default: html)
            -d          : debug (quick pass without copy or conversion)
            -r          : remove existing output folder if any


Title and subtitles are aligned on the left side by default, overlaid over the first image.
other arguments are none (no title), top (centered over the image), right (overlaid on the right).

Default format is "70px 50px 60% auto": 1st and 2nd arguments are title and subtitle font sizes,
3rd and 4th are used with left/right titles and are the vertical and horizontal positions.
These arguments use standard browser units: `px`, `%`, `auto`...

Subtitle can be removed by setting it to `""`.
