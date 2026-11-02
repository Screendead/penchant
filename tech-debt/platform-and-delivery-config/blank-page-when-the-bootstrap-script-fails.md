# The body is one script tag with no onerror, timeout, or fallback markup

**Severity:** medium

If flutter_bootstrap.js returns a 404, is blocked by a script or ad blocker, or times out on a slow connection, there is nothing else in the DOM for the browser to render. The user is left on a permanently blank page with no error message, loading indicator or retry affordance.

## Evidence

- `web/index.html:35` — `<body>\n  <script src="flutter_bootstrap.js" async></script>\n</body>`
