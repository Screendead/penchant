#!/usr/bin/env bash
# Renders the sign-in screen's tab switch frame by frame, then writes
# <out>/<name>.gif (real time), <name>-slow.gif (4x slower) and
# <name>-sheet.png (one frame in two, 32 ms apart: the switch to Create
# account on the top row, back to Sign in below).
#   tools/auth-switch-frames.sh <out-dir> <name>
set -euo pipefail
out=${1:?out dir}
name=${2:?name}
frames=$(mktemp -d)
trap 'rm -rf "$frames"' EXIT
cd "$(dirname "$0")/.."
flutter test test/auth_switch_frames_render_test.dart --dart-define=RENDER_DIR="$frames" >/dev/null
mkdir -p "$out"
palette="split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer"
ffmpeg -loglevel error -y -framerate 60 -i "$frames/frame-%03d.png" \
  -vf "scale=390:-1,$palette" "$out/$name.gif"
ffmpeg -loglevel error -y -framerate 15 -i "$frames/frame-%03d.png" \
  -vf "scale=390:-1,$palette" "$out/$name-slow.gif"
# Frames 0..30 switch to Create account and 31..61 back; keep 0, 2, ..., 22 of each.
ffmpeg -loglevel error -y -framerate 1 -start_number 0 -i "$frames/frame-%03d.png" \
  -vf "select='lt(mod(n\,31)\,24)*not(mod(mod(n\,31)\,2))',scale=200:-1,crop=200:383:0:50,tile=12x2:padding=4:color=gray" \
  -frames:v 1 "$out/$name-sheet.png"
