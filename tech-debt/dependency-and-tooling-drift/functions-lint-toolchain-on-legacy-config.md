# TypeScript, ESLint and the TS-ESLint plugins are two to three majors behind on an .eslintrc config

**Severity:** medium

`typescript` is pinned to a 4.9 range against a registry latest of 7.0.2, `eslint` to an 8.9 range against 10.8.1, and the `typescript-eslint` plugin and parser to a 5.12 range against 8.67.0.

The lint config is the legacy `.eslintrc.js` format built on `eslint-config-google`, itself unreleased for years and predating flat config, and there is no `eslint.config.js` anywhere in the tree. ESLint 9 and later default to flat config and dropped automatic `.eslintrc` discovery, so a major bump breaks the lint script outright rather than upgrading cleanly.

## Evidence

- `functions/package.json:28` — `"typescript": "^4.9.0"`
- `functions/package.json:24` — `"eslint": "^8.9.0",`
- `functions/.eslintrc.js:1` — `module.exports = {`
- **`npm outdated --prefix functions`** → `@typescript-eslint/eslint-plugin 5.62.0 5.62.0 8.67.0 ... eslint 8.57.0 8.57.1 10.8.1 ... typescript 4.9.5 4.9.5 7.0.2`
- **`find functions -maxdepth 2 -not -path '*/node_modules*'`** → `functions/.eslintrc.js`
