# admin/ pins firebase-admin two majors behind and has had no maintenance since creation

**Severity:** low

`admin/package.json` declares a 12.3 range, resolved to 12.3.0, against a registry latest of 14.2.0.

The manifest and its lockfile have a single commit each from 2024-07-28 and have never been revisited, and `admin/node_modules` carries the same July 2024 install timestamp.

## Evidence

- `admin/package.json:12` — `"firebase-admin": "^12.3.0"`
- **`python3 -c "...print(d['packages']['node_modules/firebase-admin']['version'])"`** → `12.3.0`
- **`git log --format="%h %ad %s" --date=short -- admin/package.json`** → `4b8f00b 2024-07-28 Add admin package and populateFirestore script`
