# Six gigabytes of build output plus .dart_tool, .idea and an iml file sit at the repository root

**Severity:** low

All are correctly matched by `.gitignore` rules, so none carries a tracking risk, but they are sizeable undocumented local clutter. CLAUDE.md's commands section documents CLI invocations only, and mentions no editor or IDE configuration of any kind — let alone the IntelliJ or Android Studio project configuration that the `.idea` directory and `tracker.iml` imply exists for this contributor.

## Evidence

- `.gitignore:34` — `/build/`
- `.gitignore:29` — `.dart_tool/`
- `.gitignore:19` — `.idea/`
- **`du -sh custom_lint.log error.log build .dart_tool .idea tracker.iml`** → `6.1G	build` / `324M	.dart_tool` / `20K	.idea` / `4.0K	tracker.iml`
- `tracker.iml:2` — `<module type="JAVA_MODULE" version="4">`
