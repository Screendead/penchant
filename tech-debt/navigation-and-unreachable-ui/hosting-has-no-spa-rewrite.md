# Firebase Hosting serves no rewrite, so any non-root path returns the default 404

**Severity:** low

The hosting block sets a public directory and an ignore list with no rewrites entry, so a request to any path other than the root returns Firebase Hosting's own 404 rather than `index.html`, even though `onGenerateRoute` is written to parse `/vices/:viceID/activities` from path segments.

This is masked today because no `usePathUrlStrategy` call exists, leaving Flutter web on hash URLs.

## Evidence

- `firebase.json:23` — `"hosting": {\n    "public": "build/web",\n    "ignore": [\n      "firebase.json",\n      "**/.*",\n      "**/node_modules/**"\n    ]\n  },` — no `rewrites` key, and unlike the `functions` entry (which has its own `predeploy` lint/build hook), no `predeploy` key either, so nothing rebuilds `build/web` before deploy
- `lib/main.dart:67` — `if (uri.pathSegments.length == 3 &&`
- `.gitignore:34` — `/build/`
