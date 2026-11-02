# Neither workflow lints, builds, or deploys anything under functions/

**Severity:** medium

No step in either workflow file touches that directory, and `firebase.json`'s predeploy hooks only run inside a functions deploy, a command neither workflow ever calls. The current `index.ts` holds only two unused imports with the sample function commented out, so no live server-side logic goes unvalidated today, but the gap is total: nothing in `.github/workflows` would build, lint or deploy a function if one were added.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:12` — `steps:\n      - uses: actions/checkout@v4`
- `functions/src/index.ts:16` — `// export const helloWorld = onRequest((request, response) => {\n//   logger.info("Hello logs!", {structuredData: true});\n//   response.send("Hello from Firebase!");\n// });`
