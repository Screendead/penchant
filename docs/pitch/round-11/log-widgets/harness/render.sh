#!/bin/zsh
# docs/pitch/round-11/log-widgets/harness/render.sh: builds the harness against the widget sources and writes PNGs to ../png.
set -eu
here=${0:A:h}; root=${here:h:h:h:h:h}; w=$root/ios/PenchantWidgets
bin=$(mktemp -d)/render
xcrun swiftc -O -target arm64-apple-macos14 -o $bin \
  $w/Theme.swift $w/Snapshot.swift $w/LogQueue.swift $w/LogIntents.swift $w/WeekDial.swift \
  $w/LastWeekWidget.swift $w/LogWidget.swift $w/LogVariants.swift $here/main.swift
$bin $root ${here:h}/png
