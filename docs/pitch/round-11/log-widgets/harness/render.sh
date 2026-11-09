#!/bin/zsh
# Builds the harness against the widget sources and writes the shipping Log widget's PNGs to ../final.
set -eu
here=${0:A:h}; root=${here:h:h:h:h:h}; w=$root/ios/PenchantWidgets
bin=$(mktemp -d)/render
xcrun swiftc -O -target arm64-apple-macos14 -o $bin \
  $w/Theme.swift $w/Snapshot.swift $w/LogQueue.swift $w/LogIntents.swift $w/WeekDial.swift \
  $w/LastWeekWidget.swift $w/LogWidget.swift $here/main.swift
$bin $root ${here:h}/final
