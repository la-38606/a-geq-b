#!/usr/bin/env bash
# Build the README demo media from a fresh recording:
#
#     docs/demo/aeqb-demo.mp4           the full walkthrough (H.264)
#     docs/demo/aeqb-demo-preview.gif   the first seconds, small enough to
#                                       autoplay at the top of the README
#
# Requires ffmpeg (record-demo.sh itself only needs it for the mp4).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v ffmpeg >/dev/null || { echo "error: ffmpeg is required" >&2; exit 1; }

./scripts/record-demo.sh
[ -f demo/aeqb-demo.mp4 ] || { echo "error: no mp4 was produced" >&2; exit 1; }

mkdir -p docs/demo
cp demo/aeqb-demo.mp4 docs/demo/aeqb-demo.mp4

# The preview covers example -> Prove -> typeset certificate. Palette-based
# GIF at reduced size and frame rate keeps it README-friendly.
ffmpeg -y -loglevel error -ss 1.2 -t 12.5 -i docs/demo/aeqb-demo.mp4 \
  -vf "fps=8,scale=880:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  docs/demo/aeqb-demo-preview.gif

ls -la docs/demo
