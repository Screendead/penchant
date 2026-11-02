# Every activity delete awaits an uncancelled write with no loading state

**Severity:** high

The Undo action on the record snackbar, the editor page's `_deleteActivity`, and the history page's per-row icon each await delete with no timeout, unlike the sibling write paths that wrap `set` and `update` in a ten-second timeout. Offline, the future never resolves, so nothing on screen changes: the editor's delete button is gated on a loading flag that `_deleteActivity` never sets, the history row stays tappable and can queue repeated deletes for the same document, and the Undo handler has no indicator at all.

When connectivity returns, the write is refused by the rules, and the `on FirebaseException` catch block always runs; it is only the follow-up UI action inside it — a `setState` or a snackbar — that is skipped when the captured context is no longer mounted at that later moment.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:289` — `await activityRef.delete();`
- `lib/widgets/record_new_activity_dialog.dart:256` — `        ).timeout(\n                      const Duration(seconds: 10),`
- `firestore.rules:13` — `allow write: if request.auth.uid != null && request.auth.uid == request.resource.data.ownerID;`
- `lib/vice_activity_editor_page.dart:79-84` — `} on FirebaseException catch (e) {\n      if (mounted) {\n        setState(() {\n          error = e.message ?? 'Unable to delete activity';\n        });\n      }\n    }`
- `lib/vice_activity_editor_page.dart:172` — `onPressed: loading ? null : _deleteActivity,`
- `lib/vice_activity_history_page.dart:96-98` — `} on FirebaseException catch (e) {\n                              if (context.mounted) {\n                                ScaffoldMessenger.of(context).showSnackBar(`
