#!/usr/bin/env bash
# Regenerates every committed still from index.html (headless Chrome, real time; Node 22+).
#   ./stills.sh            all of them
#   ./stills.sh states     only the ones whose name contains "states"
set -euo pipefail
cd "$(dirname "$0")"
only="${1:-}"
shot() { local out=$1; shift; [[ -z $only || $out == *"$only"* ]] || return 0; node shoot.mjs "$out" "$@"; echo "$out"; }

# Today busy and sparse, and the record frame after "Play the flow" has logged 3 Sugar.
shot stills-light.png "theme=light&frames=today-busy,today-sparse,record" 1400 1044 4200 \
  "setTimeout(() => playRecord(apps.record), 900)" 1.5 &
# Today busy, Trends with a readout, the clear day.
shot stills-dark.png "theme=dark&frames=today-busy,trends,clear&probe=22" 1400 1044 3200 "" 1.5 &
# The sheet on Earlier, Coffee history, the sign-up checklist.
shot stills-flows-light.png "theme=light&frames=record,habits,auth&record=earlier&hist=1&signup=1" 1400 1044 3200 "" 1.5 &
wait

# States the first three never show: offline with a pending entry and a refused write (scrolled to the entries),
# seven habits (two striped), and 365 days on Trends.
STATES='setTimeout(() => {
  const a = apps["today-busy"]; a.setOffline(true); a.quickLog("coffee"); a.showRejected(); a.v.today.scrollTop = 330;
  const h = apps.habits;
  h.habits.push({ id: "h6", name: "Walks", unit: "times", order: 6, archived: false }, { id: "h7", name: "Reading", unit: "minutes", order: 7, archived: false });
  h.entries.push({ id: 9001, h: "h6", d: 0, t: 610, q: 1 }, { id: 9002, h: "h7", d: 0, t: 1290, q: 30 }, { id: 9003, h: "h7", d: 3, t: 1290, q: 45 });
  h.rebuildToday(); h.go("today");
  const t = apps.trends; t.v.trends.querySelectorAll(".tctl .seg")[0].querySelectorAll("button")[3].click();
}, 900)'
shot stills-states-light.png "theme=light&frames=today-busy,habits,trends" 1400 1044 3600 "$STATES" 1.5 &
shot stills-states-dark.png "theme=dark&frames=today-busy,habits,trends" 1400 1044 3600 "$STATES" 1.5 &
# The page at phone width: the phones scale to the column.
shot stills-390.png "theme=light&frames=today-busy,record" 390 1900 3000 "" 2 &
wait
