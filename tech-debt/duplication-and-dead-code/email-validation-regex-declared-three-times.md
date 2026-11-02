# Two identical top-level emailRegex globals plus a third inline pattern

**Severity:** low

`sign_in.dart` and `register.dart` each declare a public top-level `emailRegex` with the same pattern, and `account_settings.dart` validates email with a third, looser inline pattern.

A file that imports both auth libraries and then references `emailRegex` unqualified hits an ambiguous-import error; `lib/authenticate.dart` already imports both (lines 2-3) but never references the name, so it compiles clean. The three validators can still diverge independently.

## Evidence

- `lib/sign_in.dart:4` — `final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');`
- `lib/register.dart:4` — `final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');`
- `lib/account_settings.dart:93` — `if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {`
- `lib/authenticate.dart:2-3` — imports both `register.dart` and `sign_in.dart` without referencing `emailRegex`
