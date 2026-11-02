# Whether an icon-only control has an accessible name depends on which screen it lives on

**Severity:** medium

`manage_data.dart` wraps its edit, archive and unarchive buttons in `Tooltip`, and the history and editor pages set an explicit tooltip on every `IconButton`.

The AppBar plus button on that same manage-data screen, the password-visibility toggle in `sign_in.dart`, and both day-navigation arrows in `vice_tracker.dart` carry no tooltip and no `semanticLabel`, so a screen reader announces each only as an unlabeled button.

## Evidence

- `lib/manage_data.dart:40` — `IconButton(\n            icon: const Icon(Icons.add),`
- `lib/manage_data.dart:66` — `Tooltip(\n                  message: 'Edit',\n                  child: IconButton(`
- `lib/sign_in.dart:73` — `suffixIcon: IconButton(\n                    icon: Icon(\n                      passwordIsObscured\n                          ? Icons.visibility\n                          : Icons.visibility_off,\n                    ),`
- `lib/vice_tracker.dart:127` — `IconButton(\n                    icon: const Icon(Icons.arrow_back),`
- `lib/vice_tracker.dart:146` — `IconButton(\n                    icon: const Icon(Icons.arrow_forward),`
