# account_settings.dart uses ignore comments where other files check mounted

**Severity:** medium

`_updateProfile` awaits four Firebase calls and then touches context behind two `use_build_context_synchronously` ignore comments, with no `mounted` or `context.mounted` check.

`vice_form`, `manage_data`, the editor page, the history page, and the record dialog all guard the same situation with a real `mounted` check. `sign_in.dart` does not — its async `onPressed` closure also calls `setState` after an `await` with no `mounted` guard, so it is a second unguarded site rather than a counterexample.

## Evidence

- `lib/account_settings.dart:44` — `// ignore: use_build_context_synchronously`
- `lib/account_settings.dart:51` — `// ignore: use_build_context_synchronously`
- `lib/vice_form.dart:75` — `if (mounted) {`
