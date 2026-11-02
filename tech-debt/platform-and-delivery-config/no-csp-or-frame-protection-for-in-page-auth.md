# The login and register pages can be framed and impose no script-src restriction

**Severity:** medium

No Content-Security-Policy or X-Frame-Options is configured anywhere: firebase.json has no headers key and web/index.html has no CSP meta tag. The auth surface is narrow, with only email-and-password calls and no OAuth popup, embedded webview or dart:html usage anywhere in the repository, so no third-party frame surface exists that a frame header would normally defend.

What remains is that the plain login and register pages can be embedded in a third-party iframe for UI redress, and nothing bounds what a compromised in-page script could do with a signed-in Firebase Auth session.

## Evidence

- `firebase.json:23` — `"hosting": {\n    "public": "build/web",`
- `web/index.html:3` — `<head>`
- `lib/sign_in.dart:99` — `.signInWithEmailAndPassword(`
