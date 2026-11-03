# The .metadata migration platform list tracks neither shipped platform

**Severity:** medium

The repository ships ios and macos, with ios present since the first commit, while .metadata tracks only root. Git
history shows a macos entry existed at one point and was overwritten when web support was added; the web entry left
with web/.

flutter migrate relies on this file to know which platform files were generated from templates, so template-diff
migration is unavailable for both platforms the app ships.

## Evidence

- `.metadata:13` — `migration:\n  platforms:\n    - platform: root` (no other entry)
- **`git show 591e906 -- .metadata`** → `-    - platform: macos\n+    - platform: web`
