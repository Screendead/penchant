# No build log or artifact shows the web release build running since the dependency upgrade

**Severity:** high

Neither of the two log files in the tree contains a web build invocation; one is a `flutter run` debug session, the other IDE analyzer-plugin output. The gitignored build directory holds ios, test_cache, native_assets, unit_test_assets, a build-stamp directory and a cached .dill, with no web output anywhere, so a web build has not been attempted locally since the upgrade.

That is the one command the merge workflow runs before deploying to the live hosting channel.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:23` — `run: flutter build web --release`
- **`find build -maxdepth 2`** → `build\nbuild/test_cache\nbuild/ios\nbuild/native_assets\nbuild/unit_test_assets\nbuild/cf0936cf8be5378e1c98e26bea64f9bd\nbuild/ac6bb03c0ccdeb006582a024c456901a.cache.dill.track.dill`
- **`grep -c "flutter build web" custom_lint.log error.log`** → `custom_lint.log:0\nerror.log:0`
