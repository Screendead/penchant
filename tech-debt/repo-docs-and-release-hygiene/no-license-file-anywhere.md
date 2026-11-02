# The repository grants no license, while admin/package.json claims ISC

**Severity:** high

No LICENSE, COPYING, or NOTICE file exists at the root or anywhere in tracked files; the only license texts in the tree are third-party ones inside the untracked CocoaPods checkout and the NOTICES assets in local build output. The repository is hosted on GitHub under the owner `Screendead`, and the README never mentions terms, so default all-rights-reserved applies with no statement of that anywhere a reader would find it.

`admin/package.json` declares the ISC license, the npm-init default left uncustomized alongside empty author and description fields, while `functions/package.json` declares no license and is marked private, and `pubspec.yaml` has no license concept. Nothing in the repository makes good on the terms that one manifest asserts.

## Evidence

- **`git ls-files | grep -iE "license|copying|notice"`** → (no output — no matches)
- **`git remote -v`** → `origin	https://github.com/Screendead/tracker.git (fetch)`
- **`find build -iname "*notices*"`** → `build/unit_test_assets/NOTICES.Z` plus eight more under `build/ios/`, all untracked local build output
- `README.md:1` — `# tracker` / `A new Flutter project.`
- `admin/package.json:8` — `"author": "", "license": "ISC", "description": "",`
- `functions/package.json:30` — `"private": true`
