# No CHANGELOG file exists now or at any point in history

**Severity:** medium

A repo-wide search excluding vendored directories finds none, and none was ever added or removed in git history. Two years of shipped changes, including behavioural ones such as adding the `archived` field and the `ManageData`/`AddVice` widgets, have no user- or developer-facing record of what changed between deploys, which compounds with deploys being untagged.

## Evidence

- **`find . -iname "CHANGELOG*" -not -path "*/node_modules/*" -not -path "*/.dart_tool/*" -not -path "*/build/*" -not -path "*/ios/Pods/*"`** → (no output — no matches)
- **`git ls-files | grep -i changelog`** → (no output — no matches in the current index)
- **`git log --all --diff-filter=A --name-only --format="" | grep -i changelog`** → (no output — none added at any point in history)
