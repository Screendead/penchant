#!/usr/bin/env bash
# Renders 1f's motion scenes frame by frame (test/motion_frames_render_test.dart)
# and writes, for each scene, <out>/<scene>.gif (real time), <scene>-slow.gif
# (4x slower) and <scene>-sheet.png (one frame in two, 32 ms apart).
#   tools/motion-frames.sh <out-dir>
set -euo pipefail
out=${1:?out dir}
frames=$(mktemp -d)
cd "$(dirname "$0")/.."
flutter test test/motion_frames_render_test.dart --dart-define=RENDER_DIR="$frames" >/dev/null
mkdir -p "$out"
palette="split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer"
for dir in "$frames"/*/; do
  scene=$(basename "$dir")
  ffmpeg -loglevel error -y -framerate 60 -i "$dir/frame-%03d.png" \
    -vf "scale=390:-1,$palette" "$out/$scene.gif"
  ffmpeg -loglevel error -y -framerate 15 -i "$dir/frame-%03d.png" \
    -vf "scale=390:-1,$palette" "$out/$scene-slow.gif"
  ffmpeg -loglevel error -y -framerate 1 -i "$dir/frame-%03d.png" \
    -vf "select='not(mod(n\,2))',scale=160:-1,tile=12x1:padding=4:color=gray" \
    -frames:v 1 "$out/$scene-sheet.png"
done
trash "$frames"
