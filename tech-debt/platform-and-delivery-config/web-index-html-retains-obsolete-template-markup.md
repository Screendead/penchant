# The web shell keeps an X-UA-Compatible meta tag and offers no noscript fallback

**Severity:** low

web/index.html still carries the IE-Edge compatibility meta, which targets a compatibility mode for a browser Flutter web does not support. There is also no noscript element anywhere in the page, so a client with JavaScript disabled is shown nothing at all.

## Evidence

- `web/index.html:20` — `<meta content="IE=Edge" http-equiv="X-UA-Compatible">`
- `web/index.html:21` — `<meta name="description" content="A new Flutter project.">`
- `web/manifest.json:8` — `"description": "A new Flutter project.",`
