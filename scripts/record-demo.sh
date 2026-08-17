#!/usr/bin/env bash
# Record the walkthrough video of the A>=B web interface.
#
# Builds the prover, runs the deterministic Playwright demo
# (web/e2e/demo/walkthrough.spec.js) with video capture -- the server is
# started and stopped by Playwright itself -- and leaves:
#
#     demo/aeqb-demo.webm            always
#     demo/aeqb-demo.mp4             when an H.264-capable ffmpeg is found
#
# The demo drives the real application (including the numerical SDP route,
# which needs the sdp/ virtualenv -- see sdp/README.md). Nothing is mocked,
# so a recording failure means the walkthrough found a real bug.
set -euo pipefail
cd "$(dirname "$0")/.."

dune build

if [ ! -d web/e2e/node_modules ]; then
  (cd web/e2e && npm install)
fi

rm -rf web/e2e/test-results/demo
(cd web/e2e && npx playwright test --config=demo.config.js)

video=$(find web/e2e/test-results/demo -name '*.webm' | head -n 1)
if [ -z "$video" ]; then
  echo "error: the walkthrough produced no video" >&2
  exit 1
fi

mkdir -p demo
cp "$video" demo/aeqb-demo.webm
echo "wrote demo/aeqb-demo.webm"

# Prefer a real ffmpeg; Playwright's bundled one muxes webm but cannot encode
# H.264, so an mp4 is best-effort.
if command -v ffmpeg >/dev/null 2>&1; then
  if ffmpeg -y -loglevel error -i demo/aeqb-demo.webm \
       -c:v libx264 -pix_fmt yuv420p -crf 20 demo/aeqb-demo.mp4; then
    echo "wrote demo/aeqb-demo.mp4"
  else
    echo "mp4 conversion failed; the webm is intact" >&2
  fi
else
  echo "ffmpeg not found; keeping webm only"
fi
