import 'package:flutter/material.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/errors/report_error.dart';

Future<bool> _confirmDiscard(BuildContext context) async {
  final bool? discard = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AccountCopy.signOutUnsyncedTitle),
      content: const Text(AccountCopy.signOutUnsyncedBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AccountCopy.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AccountCopy.signOutAnyway),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Signs out of [account], asking first before entries that have not synced
/// are discarded. [busy] runs each attempt, so the caller can disable its
/// control meanwhile. True once signed out; false when the user kept the
/// entries or the sign-out failed, which is reported and shown.
Future<bool> signOutAsking(
  BuildContext context,
  Account account, {
  required Future<void> Function(Future<void> Function() signOut) busy,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    try {
      await busy(account.signOut);
    } on UnsyncedEntriesException {
      if (!context.mounted || !await _confirmDiscard(context)) {
        return false;
      }
      await busy(() => account.signOut(discardUnsynced: true));
    }
    return true;
  } catch (e, stack) {
    reportError(e, stack, context: 'while signing out');
    messenger.showSnackBar(
      SnackBar(content: Text(AccountCopy.signOutFailed(authErrorMessage(e)))),
    );
    return false;
  }
}
