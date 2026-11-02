# A timed-out write still commits later, and the retry it invites duplicates it

**Severity:** high

The record dialog and the editor both wrap their write in a ten-second timeout whose `onTimeout` raises `TimeoutException`, and both show the user a request-timed-out message. The timeout abandons only the local await; the mutation stays queued in the SDK and is sent and committed once connectivity returns.

A user who sees the message and presses Record or Save again is adding a second write on top of one that will still succeed, and because the create path mints a fresh document reference on every press, the retry produces two activity documents once the device reconnects.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:256` — `  ).timeout(\n                      const Duration(seconds: 10),\n                      onTimeout: () => Future.error(TimeoutException(null)),\n                    );`
- `lib/widgets/record_new_activity_dialog.dart:267` — `setState(() {\n                    error = 'Request timed out';\n                  });`
- `lib/widgets/record_new_activity_dialog.dart:247` — `final DocumentReference<Map<String, dynamic>> activityRef =\n                    FirebaseFirestore.instance.collection('activities').doc();`
- `lib/vice_activity_editor_page.dart:106` — `}).timeout(\n        const Duration(seconds: 10),\n        onTimeout: () => Future.error(TimeoutException(null)),\n      );`
