# hosting.public points at a gitignored build/web with no predeploy hook, unlike the functions block

**Severity:** medium

The functions block declares predeploy hooks that lint and build, while the hosting block declares none. build/ is gitignored, so neither version control nor firebase.json guarantees build/web is fresh, non-empty or present at deploy time; that guarantee lives only inside the GitHub Actions workflow, which builds immediately before deploying.

In the current checkout build/ holds a stray cache.dill.track.dill file plus ios, native_assets, test_cache and unit_test_assets artifacts and a hash-named directory, but no web subdirectory, so a manual hosting deploy from here would publish nothing.

## Evidence

- `firebase.json:17` — `"predeploy": [\n        "npm --prefix \"$RESOURCE_DIR\" run lint",\n        "npm --prefix \"$RESOURCE_DIR\" run build"\n      ]`
- `firebase.json:24` — `"public": "build/web",`
- `.gitignore:34` — `/build/`
- **`ls -la /Users/jacklusher/development/tracker/build`** → `-rw-r--r--@  1 jacklusher  staff  61495592 Jul 23 08:50 ac6bb03c0ccdeb006582a024c456901a.cache.dill.track.dill\ndrwxr-xr-x@  5 jacklusher  staff       160 Jul 22 20:44 cf0936cf8be5378e1c98e26bea64f9bd\ndrwxr-xr-x@ 11 jacklusher  staff       352 Jul 23 09:07 ios\ndrwxr-xr-x@  3 jacklusher  staff        96 Jul 22 20:48 native_assets\ndrwxr-xr-x@  3 jacklusher  staff        96 Jul 22 20:48 test_cache\ndrwxr-xr-x@  9 jacklusher  staff       288 Jul 23 08:38 unit_test_assets`
