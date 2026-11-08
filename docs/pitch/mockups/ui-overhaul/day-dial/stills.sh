#!/bin/sh
# Re-renders the three stills from index.html with headless Chrome (see shoot.mjs).
set -e
cd "$(dirname "$0")"
node shoot.mjs stills-light.png 1400x2410 "theme=light" 4000
node shoot.mjs stills-dark.png 1400x2410 "theme=dark&state=clear,hist" 4500
node shoot.mjs stills-record.png 1360x915 "theme=dark&board=record" 5000
