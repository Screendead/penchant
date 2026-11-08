import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_wiring.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widget_bridge/log_queue.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';
import 'package:tracker/writes/rejected_writes.dart';

// Inside a BGAppRefreshTask, which iOS ends after about 30 seconds: the
// session and the key get this long, a write up to settleWrite's 10 s more.
const Duration backgroundReadyWithin = Duration(seconds: 12);

/// One flush of the widgets' queue from a headless engine that iOS started for
/// a background refresh (ios/Runner/WidgetBridge.swift). It writes only what
/// the app would: the signed-in user's logs, sealed. Without the session or
/// the key in time it writes nothing and the logs stay queued.
Future<BackgroundFlushOutcome> runBackgroundFlush({
  required Future<void> Function() initialize,
  required List<Override> overrides,
  required DateTime Function() now,
  Duration readyWithin = backgroundReadyWithin,
}) async {
  await initialize();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      ...overrides,
      rejectedWritesProvider.overrideWith(BackgroundRejectedWrites.new),
    ],
  );
  // Holds the key chain (autoDispose) for the whole run, so the sealer read
  // below is the one the key resolved to.
  container.listen(sealerProvider, (_, _) {});
  try {
    final AsyncValue<User?> user = await _settled(
      container,
      userProvider,
      readyWithin,
    );
    final String? uid = user.value?.uid;
    if (uid == null) {
      return user.hasValue
          ? BackgroundFlushOutcome.blocked
          : BackgroundFlushOutcome.retry;
    }
    if (container.read(e2eeEnabledProvider)) {
      final AsyncValue<JournalKeyState> key = await _settled(
        container,
        journalKeyProvider,
        readyWithin,
      );
      switch (key.value) {
        case KeyReady():
          break;
        case KeyNeedsRecovery():
          return BackgroundFlushOutcome.blocked;
        case KeyUnknown() || null:
          return BackgroundFlushOutcome.retry;
      }
      // TrackerWrites without a sealer would store the log without its
      // sealed field.
      if (container.read(sealerProvider) == null) {
        return BackgroundFlushOutcome.retry;
      }
    }
    final DateTime? next = await flushQueuedLogs(
      bridge: container.read(widgetBridgeProvider),
      writes: container.read(trackerWritesProvider),
      rejected: container.read(rejectedWritesProvider.notifier),
      uid: uid,
      now: now(),
      keepRefused: true,
    );
    return next == null
        ? BackgroundFlushOutcome.flushed
        : BackgroundFlushOutcome.retry;
  } on Object catch (e, stack) {
    reportError(e, stack, context: 'while flushing $widgetLogWhat');
    return BackgroundFlushOutcome.retry;
  } finally {
    container.dispose();
  }
}

// The provider's first value that is not loading, kept listened to meanwhile:
// a read alone would pause a stream provider. Loading if none came in time.
Future<AsyncValue<T>> _settled<T>(
  ProviderContainer container,
  ProviderListenable<AsyncValue<T>> provider,
  Duration within,
) async {
  final Completer<AsyncValue<T>> settled = Completer<AsyncValue<T>>();
  final ProviderSubscription<AsyncValue<T>> sub = container.listen(provider, (
    _,
    AsyncValue<T> next,
  ) {
    if (!next.isLoading && !settled.isCompleted) {
      settled.complete(next);
    }
  }, fireImmediately: true);
  try {
    return await settled.future.timeout(
      within,
      onTimeout: () => AsyncValue<T>.loading(),
    );
  } finally {
    sub.close();
  }
}

/// RejectedWrites without the start-up reconcile, which would claim earlier
/// launches' journalled writes and report a refusal to a banner nobody sees.
/// The app's next launch reconciles them instead.
class BackgroundRejectedWrites extends RejectedWrites {
  @override
  List<RejectedWrite> build() => const <RejectedWrite>[];
}
