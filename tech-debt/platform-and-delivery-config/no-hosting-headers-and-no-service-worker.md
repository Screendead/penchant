# The hosting block declares no headers and current Flutter emits no service worker by default

**Severity:** high

firebase.json's hosting block has no headers key, so no Cache-Control, Content-Security-Policy, HSTS, X-Frame-Options or Referrer-Policy is asserted for any response; Firebase Hosting auto-adds HSTS but the others exist only when declared.

Separately, web/index.html loads the single flutter_bootstrap.js script with no service-worker version variable, matching the newer template, and current Flutter no longer generates or manages a service worker by default, with nothing here opting back in. Both layers that could bound how long a client keeps running a stale build are therefore absent, for an app that authenticates users and redeploys on every push to master.

## Evidence

- `firebase.json:23` — `"hosting": {\n    "public": "build/web",\n    "ignore": [\n      "firebase.json",\n      "**/.*",\n      "**/node_modules/**"\n    ]\n  },`
- `web/index.html:36` — `<script src="flutter_bootstrap.js" async></script>`
- **`WebFetch https://docs.flutter.dev/platform-integration/web/faq`** → `Flutter no longer generates or manages a service worker by default. ... users might use a cached version of your app for the duration defined by your cache headers.`
- **`WebFetch https://groups.google.com/g/firebase-talk/c/S6XDEV6TVhk`** → `Firebase Hosting automatically adds HSTS headers to all hosted sites, but we currently don't support the preload option.`
