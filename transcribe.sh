#!/usr/bin/env bash

# Small shell script to more easily automatically download and transcribe live stream VODs.
# This uses YT-DLP, ffmpeg and the CPP version of Whisper: https://github.com/ggerganov/whisper.cpp
# Use `./transcribe-vod help` to print help info.

# MIT License

# Copyright (c) 2022 Daniils Petrovs

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -Eeuo pipefail

# You can find how to download models in the OG repo: https://github.com/ggerganov/whisper.cpp/#usage
# MODEL_PATH="${MODEL_PATH:-models/ggml-base.en.bin}" # Set to a multilingual model if you want to translate from foreign lang to en
# WHISPER_EXECUTABLE="${WHISPER_EXECUTABLE:-whisper}" # Where to find the whisper.cpp executable
# WHISPER_LANG="${WHISPER_LANG:-en}" # Set to desired lang to translate from

MODEL_PATH="models/ggml-small.bin" # Set to a multilingual model if you want to translate from foreign lang to en
WHISPER_EXECUTABLE="./main" # Where to find the whisper.cpp executable
WHISPER_LANG="${WHISPER_LANG:-en}" # Set to desired lang to translate from

temp_dir="tmp"
source_url="$1"
result_dir="res"

# For downloading whole vod put start_point as 0 and duration as -1

start_point="$2"
duration="$3"

msg() {
	echo >&2 -e "${1-}"
}

cleanup() {
	msg "Cleaning up..."
	rm -rf "${temp_dir}" "vod-resampled.wav" "vod-resampled.wav.srt"
}

print_help() {
	echo "Usage: ./transcribe-vod <video_url> <start_point> <duration>"
    echo "Use start_point as 00:00:00 if you want to start from the beginning and duration as -1"
	echo "See configurable env variables in the script"
	echo "This will produce an MP4 muxed file called res.mp4 in the results directory"
	echo "Requirements: ffmpeg yt-dlp whisper"
	echo "Whisper needs to be built into the main binary with make, then you can rename it to something like 'whisper' and add it to your PATH for convenience."
	echo "E.g. in the root of Whisper.cpp, run: 'make && cp ./main /usr/local/bin/whisper'"
}

check_requirements() {
	if ! command -v ffmpeg &>/dev/null; then
		echo "ffmpeg is required (https://ffmpeg.org)."
		exit 1
	fi

	if ! command -v yt-dlp &>/dev/null; then
		echo "yt-dlp is required (https://github.com/yt-dlp/yt-dlp)."
		exit 1
	fi

	if ! command -v "$WHISPER_EXECUTABLE" &>/dev/null; then
		echo "Whisper is required (https://github.com/ggerganov/whisper.cpp)."
		exit 1
	fi
}

if [[ "$1" == "help" ]]; then
	print_help
	exit 0
fi

check_requirements

mkdir -p $temp_dir
mkdir -p $result_dir

if [[ "$3" == "-1" ]]; then
    msg "Downloading full VOD..."

    # Optionally add --cookies-from-browser BROWSER[+KEYRING][:PROFILE][::CONTAINER] for members only VODs
    yt-dlp \
    	-f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
    	--embed-thumbnail \
    	--embed-chapters \
    	--xattrs \
    	"${source_url}" -o "${temp_dir}/vod.mp4"
else 
    msg "Dowloading partial VOD..."

    org_url="$(yt-dlp -g "${source_url}")"
    vid_aud_url=(${org_url//'\n'/ })
    video_url="${vid_aud_url[0]}"
    audio_url="${vid_aud_url[1]}"

    ffmpeg -ss "${start_point}" -i "${video_url}" -ss "${start_point}" -i "${audio_url}" -map 0:v -map 1:a -t "${duration}" -c:v libx264 -c:a aac "${temp_dir}/vod.mp4"
fi

msg "Extracting audio and resampling..."

ffmpeg -i "${temp_dir}/vod.mp4" \
	-hide_banner \
	-loglevel error \
	-ar 16000 \
	-ac 1 \
	-c:a \
	pcm_s16le -y "vod-resampled.wav"

msg "Transcribing to subtitle file..."
msg "Whisper specified at: ${WHISPER_EXECUTABLE}"

$WHISPER_EXECUTABLE \
	-m "${MODEL_PATH}" \
	-l "${WHISPER_LANG}" \
	-f "vod-resampled.wav" \
	-t 8 \
	-osrt \
	--translate

msg "Embedding subtitle track..."

ffmpeg -i "${temp_dir}/vod.mp4" \
	-hide_banner \
	-loglevel error \
	-i "vod-resampled.wav.srt" \
	-c copy \
	-c:s mov_text \
	-y "${result_dir}/res.mp4"

cleanup

msg "Done! Your finished file is ready: ${result_dir}/res.mp4"