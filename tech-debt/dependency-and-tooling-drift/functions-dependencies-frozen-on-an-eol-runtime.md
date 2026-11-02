# functions/package.json has one commit ever and pins an end-of-life Node runtime

**Severity:** high

The `engines` field pins Node 18, `firebase-admin` to a 12.x range and `firebase-functions` to a 5.x range, while the registry's latest majors are 14.2.0 and 7.3.2 — two ahead of each. Node 18 reached upstream end of life on 2025-04-30.

The manifest has had exactly one commit, its 2024-07-27 initial add, and the lockfile moved only through three narrow dependabot bumps of nested packages in late 2024, two of which reached master as July 2026 merges, leaving the direct ranges and the runtime target untouched for over two years.

## Evidence

- `functions/package.json:14` — `"node": "18"`
- `functions/package.json:18` — `"firebase-admin": "^12.1.0",`
- `functions/package.json:19` — `"firebase-functions": "^5.0.0"`
- **`npm outdated --prefix functions`** → `firebase-admin 12.3.0 12.7.0 14.2.0 ... firebase-functions 5.0.1 5.1.1 7.3.2`
- **`git log --format="%h %ad %s" --date=short -- functions/package.json`** → `8f02d16 2024-07-27 Add Firebase configuration files and dependencies`
- **`git log -3 --format="%h %ad %s" --date=short -- functions/package-lock.json`** → `be38d9d 2026-07-22 Merge pull request #5 ... micromatch-4.0.8`
