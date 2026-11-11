import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/providers/sync_status_provider.dart';

/// How long Quit waits for the server to acknowledge what was written. The
/// Mac app delegate hides the windows first and exits by itself a little
/// after this (macos/Runner/AppDelegate.swift), so keep the two in step.
const Duration quitSyncLimit = Duration(seconds: 3);

/// Lets the app exit once every write is acknowledged or [limit] has passed.
/// A write still unsent then stays in Firestore's queue on disk and goes on
/// the next launch.
Future<AppExitResponse> exitWhenSynced(
  Future<void> Function() pendingWrites, {
  Duration limit = quitSyncLimit,
}) async {
  try {
    await pendingWrites().timeout(limit);
  } on Object {
    // Offline, signed out mid-wait or out of time: exit all the same.
  }
  return AppExitResponse.exit;
}

/// Answers the desktop's Quit request (Cmd+Q) through [exitWhenSynced].
final quitWhenSyncedProvider = Provider<void>((ref) {
  final AppLifecycleListener listener = AppLifecycleListener(
    onExitRequested: () =>
        exitWhenSynced(ref.read(pendingWritesWaiterProvider)),
  );
  ref.onDispose(listener.dispose);
});
