# functions/src/index.ts does not compile, and the predeploy hook runs exactly that build

**Severity:** critical

The two live import statements, `onRequest` and `logger`, are unused because every line that would consume them is commented out, and `tsconfig.json` sets `noUnusedLocals`, so `tsc` exits 2 with two TS6133 errors against the versions the lockfile pins. `firebase.json`'s functions predeploy hook runs lint and then build, and the eslint config treats the same condition as a non-blocking warning while the compiler treats it as a hard error, so lint passes and build aborts any functions deploy before Firebase is contacted. The only logging facility the scaffold sets up for itself is therefore inert, and the file could not build even to try.

## Evidence

- `functions/src/index.ts:10` — `import {onRequest} from "firebase-functions/v2/https";`
- `functions/src/index.ts:11` — `import * as logger from "firebase-functions/logger";`
- `functions/tsconfig.json:5` — `"noUnusedLocals": true,`
- `firebase.json:18` — `"npm --prefix \"$RESOURCE_DIR\" run lint", "npm --prefix \"$RESOURCE_DIR\" run build"`
- **`npm --prefix functions run build`** → `src/index.ts(10,1): error TS6133: 'onRequest' is declared but its value is never read.\nsrc/index.ts(11,1): error TS6133: 'logger' is declared but its value is never read.\nEXIT_CODE:2`
- **`npm --prefix functions run lint`** → `10:9   warning  'onRequest' is defined but never used  @typescript-eslint/no-unused-vars\n  11:13  warning  'logger' is defined but never used     @typescript-eslint/no-unused-vars` (0 errors, 2 warnings)
