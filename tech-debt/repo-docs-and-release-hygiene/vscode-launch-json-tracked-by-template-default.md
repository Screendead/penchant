# The .vscode directory is tracked because the stock ignore line was left commented out

**Severity:** low

The root `.gitignore`'s `.vscode` exclusion is disabled by the unedited template comment explaining that it is commented out by default, rather than by a project decision to version editor config. `.vscode/launch.json` is consequently tracked, and nothing gates a future personal launch-config edit carrying breakpoints, custom arguments, or local paths from being committed alongside it.

## Evidence

- `.gitignore:24` — `#.vscode/`
- **`git ls-files .vscode`** → `.vscode/launch.json`
