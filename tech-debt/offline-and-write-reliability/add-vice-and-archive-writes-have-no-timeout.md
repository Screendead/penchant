# The add-vice save and both archive toggles await writes with no timeout and stay enabled

**Severity:** medium

`vice_form.dart` awaits an `add` (or, editing, an `update`) with no timeout and declares no loading field at all, and `manage_data.dart`'s archive and unarchive icon buttons await `update` inline with no per-row pending state. Offline, each future never resolves, so the only symptom is that nothing happens when the control is pressed, and it can be pressed again.

## Evidence

- `lib/vice_form.dart:46` — `.addVice(ownerID: user.uid, name: name, unit: unit!);`
- `lib/manage_data.dart:82` — `onPressed: () async {\n                            try {\n                              await FirebaseFirestore.instance\n                                  .collection('vices')\n                                  .doc(vice.id)\n                                  .update({\n                                'archived': false,\n                              });`
- `lib/manage_data.dart:106` — `onPressed: () async {\n                            try {\n                              await FirebaseFirestore.instance\n                                  .collection('vices')\n                                  .doc(vice.id)\n                                  .update({\n                                'archived': true,\n                              });`
