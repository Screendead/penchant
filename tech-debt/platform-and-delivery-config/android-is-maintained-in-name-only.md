# Four platform trees are tracked, only web is ever built, and nothing states which ship

**Severity:** medium

Both workflows run flutter build web exclusively. Git history shows android/ touched by exactly three commits ever, the last an app-icon change in July 2024, against nineteen commits touching ios/ and seven touching macos/.

Nothing in README.md, CLAUDE.md or anywhere else states which of the four maintained platforms are actually shipped rather than merely scaffolded.

## Evidence

- **`git log --oneline --all -- android/`** → `8a4c8f9 Add app icon\n01f4585 \`flutterfire configure\`\n2b5c55c first commit`
- **`git log --oneline --all -- ios/ | wc -l`** → `19`
- **`git log -1 --format=%ai -- android/app/build.gradle`** → `2024-07-15 20:12:37 +0100`
- `.github/workflows/firebase-hosting-pull-request.yml:24` — `- name: Build\n        run: flutter build web`
