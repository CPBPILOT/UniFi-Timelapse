#!/bin/bash

# Base directory for snapshots
SNAP_BASE="/home/cbourque/auto_timelapse"
# "/nas/data/Development/UniFi/TimeLapse/UniFi-Timelapse/UniFi-Snaps"
OUT_DIR="$SNAP_BASE/timelapse"
DATE_EXT=`date '+%F %H:%M'`

# Associative array to store camera names and their RTSP URLs
declare -A CAMS

# Add cameras to the CAMS array
CAMS["REAR_LOT"]="rtsps://10.20.20.167:7441/3DIxsZuApyyKa9iO?enableSrtp"

# Enable verbose output if running in a terminal
if [[ -z $VERBOSE && -t 1 ]]; then
  VERBOSE=1
fi

# Function to log messages to stdout if verbose mode is enabled
log()
{
  if [ ! -z $VERBOSE ]; then echo "$@"; fi
}

# Function to log error messages to stderr
logerr() 
{ 
  echo "$@" 1>&2; 
}

# Function to create a directory if it doesn't exist
createDir()
{
  if [ ! -d "$1" ]; then
    mkdir "$1"
    # check error here
  fi  
}

# Function to capture a snapshot from a camera
getSnap() {
  snapDir="$SNAP_BASE/$1"
  if [ ! -d "$snapDir" ]; then
    mkdir -p "$snapDir"
    # check error here
  fi
  
  snapFile="$snapDir/$1 - $DATE_EXT.jpg"

  log savingSnap "$2" to "$snapFile"

 # Remove images older than 360 days
  log "Removing images older than 360 days in $snapDir"
  find "$snapDir" -type f -name "*.jpg" -mtime +360 -exec rm {} \; 

  # Capture the snapshot using ffmpeg
  ffmpeg -rtsp_transport tcp -i "$2" -frames:v 1 -update 1 "$snapFile"
}

# Function to create a timelapse video from snapshots
createMovie()
{
  snapDir="$SNAP_BASE/$1"
  snapTemp="$snapDir/temp-$DATE_EXT"
  snapFileList="$snapDir/temp-$DATE_EXT/files.list"
  
  if [ ! -d "$snapDir" ]; then
    logerr "Error: No media files in '$snapDir'"
    exit 2
  fi

  createDir "$snapTemp"

  # Determine which images to include based on the second parameter
  if [ "$2" = "today" ]; then
    log "Creating video of $1 from today's images"
    ls "$snapDir/"*`date '+%F'`*.jpg | sort > "$snapFileList"
  elif [ "$2" = "yesterday" ]; then
    log "Creating video of $1 from yesterday's images"
    ls "$snapDir/"*`date '+%F' -d "1 day ago"`*.jpg | sort > "$snapFileList"
  elif [ "$2" = "file" ]; then
    if [ ! -f "$3" ]; then
      logerr "ERROR: File '$3' not found"
      exit 1
    fi
    log "Creating video of $1 from images in $3"
    cp "$3" "$snapFileList"
  else
    log "Creating video of $1 from all images"
    ls "$snapDir/"*.jpg | sort > "$snapFileList"
  fi

  # Change to the temporary directory
  cwd=`pwd`
  cd "$snapTemp"
  x=1

  # Create sequentially numbered symlinks to the images
  while IFS= read -r file; do
    counter=$(printf %06d $x)
    ln -s "../`basename "$file"`" "./$counter.jpg"
    x=$(($x+1))
  done < "$snapFileList"

  if [ $x -eq 1 ]; then
    logerr "ERROR: No files found"
    exit 2
  fi

  createDir "$OUT_DIR"
  outfile="$OUT_DIR/$1 - $DATE_EXT.mp4"

  # Create the video using ffmpeg
  ffmpeg -r 24 -start_number 1 -i "$snapTemp/"%06d.jpg -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p "$outfile" -hide_banner -loglevel panic

  log "Created $outfile"

  # Clean up temporary files
  cd $cwd
  rm -rf "$snapTemp"
}

# Command-line argument handling
case $1 in
  # Saves snapshots for specified cameras
  savesnap)
    for ((i = 2; i <= $#; i++ )); do
      if [ -z "${CAMS[${!i}]}" ]; then
        logerr "ERROR: Can't find camera '${!i}'"
      else
        getSnap "${!i}" "${CAMS[${!i}]}"
      fi
    done
  ;;

  # Creates timelapse video
  createvideo)
    createMovie "${2}" "${3}" "${4}"
  ;;

  # Default case for invalid arguments
  *)
    logerr "Usage:"
    logerr "$0 savesnap \"camera name\""
    logerr "$0 createvideo \"camera name\" [today|yesterday|all|file filename]"
  ;;

esac

