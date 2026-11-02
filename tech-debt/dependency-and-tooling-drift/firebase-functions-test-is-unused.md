# A test-only dependency with no test file, directory, or script

**Severity:** low

`firebase-functions-test` is declared in `devDependencies` but nothing under `functions/` imports it, and there is no test file, test directory or test script anywhere in that tree.

It adds install weight and lockfile entries for tooling that does nothing.

## Evidence

- `functions/package.json:27` — `"firebase-functions-test": "^3.1.0",`
- **`find functions -iname '*test*' -not -path '*/node_modules*'`** → `(no output — no test files exist)`
- **`grep -rln 'firebase-functions-test' functions --include=*.ts --include=*.js | grep -v node_modules`** → `(no output — package is never referenced in source)`
