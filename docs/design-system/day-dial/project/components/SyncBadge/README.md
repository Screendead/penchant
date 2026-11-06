# SyncBadge

The app bar's sync state, and the per-entry "Not yet synced" mark.

**Provide:** whether the device is offline, and for a row, whether its entry has pending writes.

- App bar (right): a 32pt pill with an 18px cloud icon and Text 500 12px `muted`: cloudok "Synced", or cloudoff "Offline". The wordmark menu button sits left: Display 900 21px with a `muted` chevron.
- Rows: under the amount, cloudup at 13px with "Not yet synced" in Text 12px `muted`. The row's bead is drawn pending.
- The menu's footer repeats the state: "All entries synced · last at 21:08".

**Do not** turn it red or animate it while online. Offline is a fact, not an error.
