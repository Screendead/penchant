# The minimatch 11 override breaks the firebase-tools paths that call minimatch as a function

**Severity:** medium

`tests/firestore-rules/package.json` overrides `minimatch` to 11.0.1 to clear Dependabot alert GHSA-g3hv-75wg-m249, which lists no patched version below 11.0.1. `firebase-tools` 15.34.2 and its `superstatic` declare `minimatch` ^3 and ^6 and call `require("minimatch")(path, glob)`; minimatch 9 and later export an object, so each call throws `minimatch is not a function`.

The rules suite and the deploy job's `firebase deploy --only firestore` never reach those calls. Functions and App Hosting deploys, `crashlytics:sourcemap:upload` and hosting emulation through this install would fail (`fsAsync.readdirRecursive` and superstatic's `patterns.js`); Hosting deploy lists files through glob's `sync` and still works. Widening the deploy job to functions or App Hosting needs this resolved first.

## Evidence

- `tests/firestore-rules/package.json` — `"minimatch": "11.0.1"` under `overrides`
- **`cd tests/firestore-rules && node -e "require('firebase-tools/lib/fsAsync.js').readdirRecursive({path:'.',ignoreStrings:['*.log']}).catch(e=>console.log(e.message))"`** → `minimatch is not a function`
- **`node -e "require('superstatic/lib/utils/patterns.js').configMatcher('/a',{glob:'**'})"`** → `minimatch is not a function`
- `.github/workflows/deploy-firestore.yml` — the deploy step passes `--only firestore`
