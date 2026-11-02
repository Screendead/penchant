# The .metadata migration platform list omits ios and android and lost its macos entry

**Severity:** medium

The repository has ios, android, macos and web platform directories, with ios and android present since the first commit, while .metadata tracks only root and web. Git history shows a macos entry existed at one point and was overwritten rather than appended when web support was added.

flutter migrate relies on this file to know which platform files were generated from templates, so template-diff migration is unavailable for three of the four platforms the app ships.

## Evidence

- `.metadata:13` — `migration:\n  platforms:\n    - platform: root\n      create_revision: b0850beeb25f6d5b10426284f506557f66181b36\n      base_revision: b0850beeb25f6d5b10426284f506557f66181b36\n    - platform: web`
- **`git show 591e906 -- .metadata`** → `-    - platform: macos\n+    - platform: web`
- **`ls -d ios android macos web`** → `android\nios\nmacos\nweb`
