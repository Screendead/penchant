# Manage Data's loading and empty branches render without a Scaffold and hide the add-vice control

**Severity:** medium

The build guards test the vice list and then the activity list in sequence, so a user who has added vices but recorded nothing hits the second guard and never reaches the real `Scaffold`. The loading, no-vices and no-activities branches each return a bare `Center` with no `Scaffold`, no `AppBar` and no Material background, while the route hosting them is pushed as a fullscreen dialog, leaving no close affordance.

The add-vice button lives in the `AppBar`; the archive/unarchive and edit controls live in each list item's trailing row within the body's `ListView.builder`. Both are unreachable in these branches not because they share the `AppBar`, but because the early-return `Center` widgets skip the whole `Scaffold` — body, `ListView`, and all.

## Evidence

- `lib/manage_data.dart:19` — `return const Center(`
- `lib/manage_data.dart:30` — `if (viceActivityList.isEmpty) {\n      return const Center(\n        child: Text('No activities found'),\n      );\n    }`
- `lib/manage_data.dart:36` — `return Scaffold(\n      appBar: AppBar(\n        title: const Text('Your Vices'),`
- `lib/manage_data.dart:66` — `Tooltip(\n                  message: 'Edit',\n                  child: IconButton(\n                    icon: const Icon(Icons.edit),` (inside the `ListTile` trailing row, not the `AppBar`)
- `lib/main.dart:93` — `fullscreenDialog: true,`
