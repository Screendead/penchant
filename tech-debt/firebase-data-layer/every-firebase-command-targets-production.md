# The main checkout's active Firebase project is production, and there is no staging project

**Severity:** medium

`.firebaserc`'s `default` alias is `demo-tracker`, so a `firebase` command without `--project` in a fresh clone or a
worktree targets the demo project. But `firebase use` records an active project per directory in the CLI's
configstore, and that entry wins over `.firebaserc`: the configstore on Jack's Mac maps
`~/development/tracker` to `screendead-vice-tracker`, so in the main checkout a bare `firebase deploy`
or `firestore:*` command still reaches production until that entry is cleared (`firebase use --clear` there).

There is also no staging project in which to try a rules or index deploy before production; a separate beta project
is the open call `r2-testflight`.

## Evidence

- `~/.config/configstore/firebase-tools.json` — `"activeProjects": { "~/development/tracker": "screendead-vice-tracker", ... }`
- firebase-tools 15.34.2 `lib/command.js` `applyRC` — `options.project = options.project ?? activeProject;` before it reads `rc.projects`
- `.github/workflows/deploy-firestore.yml:45` — `--project screendead-vice-tracker --non-interactive`
