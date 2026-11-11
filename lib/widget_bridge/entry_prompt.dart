import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widget_bridge/log_queue.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/what_was_going_on.dart';

/// An entry logged by a widget or the menu bar whose "What was going on?" was
/// tapped. Ids only: what is picked is journal content, sealed in the app.
typedef EntryPrompt = ({String activityID, String viceID});

// EntryPrompt in ios/Runner/WidgetBridge.swift keeps the tapped entry until
// Dart takes it, and says when there is a new one.
class EntryPromptChannel {
  const EntryPromptChannel([
    this._channel = const MethodChannel('com.screendead.penchant/entry_prompt'),
  ]);

  final MethodChannel _channel;

  /// The entry waiting to be asked about, once: native forgets it.
  Future<EntryPrompt?> take() async {
    try {
      final Map<Object?, Object?>? taken = await _channel
          .invokeMapMethod<Object?, Object?>('take');
      final Object? id = taken?['id'];
      final Object? viceID = taken?['viceID'];
      if (id is! String || id.isEmpty || viceID is! String || viceID.isEmpty) {
        return null;
      }
      return (activityID: id, viceID: viceID);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while opening an entry from a widget');
      return null;
    }
  }

  /// Called when native has a new entry to [take]; null stops listening.
  void onChanged(void Function()? changed) {
    _channel.setMethodCallHandler(
      changed == null
          ? null
          : (MethodCall call) async {
              if (call.method != 'changed') {
                throw MissingPluginException();
              }
              changed();
            },
    );
  }
}

final entryPromptChannelProvider = Provider<EntryPromptChannel>(
  (ref) => const EntryPromptChannel(),
);

/// The entry waiting for Today to ask about it. It waits through sign-in and
/// the journal key loading.
final pendingEntryPromptProvider =
    NotifierProvider<PendingEntryPrompt, EntryPrompt?>(PendingEntryPrompt.new);

class PendingEntryPrompt extends Notifier<EntryPrompt?> {
  @override
  EntryPrompt? build() => null;

  void request(EntryPrompt prompt) => state = prompt;

  void clear() => state = null;
}

/// The pending entry once the journal key has loaded, without which neither
/// the queued log nor what is picked can be written, and the habits have
/// loaded opened with it, so its habit can be found.
final entryPromptReadyProvider = Provider<EntryPrompt?>((ref) {
  final EntryPrompt? pending = ref.watch(pendingEntryPromptProvider);
  if (pending == null || ref.watch(sealerProvider) == null) {
    return null;
  }
  final AsyncValue<List<Vice>> vices = ref.watch(viceListProvider);
  return vices.hasValue && !vices.isLoading ? pending : null;
});

/// Takes an entry the launch came with and hears later ones, for the life of
/// the app; MyApp keeps it alive.
final entryPromptListenerProvider = Provider<void>((ref) {
  if (!widgetsSupported) {
    return;
  }
  final EntryPromptChannel channel = ref.watch(entryPromptChannelProvider);
  bool disposed = false;
  Future<void> take() async {
    final EntryPrompt? prompt = await channel.take();
    if (prompt != null && !disposed) {
      ref.read(pendingEntryPromptProvider.notifier).request(prompt);
    }
  }

  channel.onChanged(() => unawaited(take()));
  ref.onDispose(() {
    disposed = true;
    channel.onChanged(null);
  });
  unawaited(take());
});

enum EntryPromptState {
  /// The entry is written, or its create is issued: ask, then update it.
  ready,

  /// Undone since: nothing to ask about.
  undone,

  /// Still queued, as it could not be written (offline with no key, say).
  unsaved,
}

/// Makes sure [activityID] exists before anything changes it: a log still in
/// the widget queue is written now, through [flusher] so no other flush
/// creates it again afterwards, which would overwrite what is picked. A log
/// already gone from the queue was written (native hands over only the last
/// log, and an Undo clears that).
Future<EntryPromptState> prepareEntryPrompt({
  required WidgetBridge bridge,
  required WidgetLogFlusher? flusher,
  required String uid,
  required String activityID,
}) async {
  bool queued(List<QueuedLog> logs, QueuedLogOp op) => logs.any(
    (QueuedLog l) => l.uid == uid && l.id == activityID && l.op == op,
  );
  final List<QueuedLog> before = await bridge.pendingLogs();
  if (queued(before, QueuedLogOp.delete)) {
    return EntryPromptState.undone;
  }
  if (!queued(before, QueuedLogOp.log)) {
    return EntryPromptState.ready;
  }
  if (flusher == null) {
    return EntryPromptState.unsaved;
  }
  await flusher.writeNow(activityID);
  final List<QueuedLog> after = await bridge.pendingLogs();
  if (queued(after, QueuedLogOp.delete)) {
    return EntryPromptState.undone;
  }
  return queued(after, QueuedLogOp.log)
      ? EntryPromptState.unsaved
      : EntryPromptState.ready;
}

const String entryUndoneNotice = 'That entry was undone.';
const String entryHabitGoneNotice =
    "That entry's habit is not in Penchant any more.";
const String entryUnsavedNotice =
    'That entry is not saved yet. Penchant will save it, then you can add '
    'what was going on from Today.';

/// Today's handling of a widget's or the menu bar's "What was going on?":
/// the entry is written first if still queued, then the picker opens on it.
Future<void> openEntryPrompt(
  BuildContext context,
  WidgetRef ref,
  EntryPrompt prompt,
) async {
  final String? uid = ref.read(userProvider).value?.uid;
  if (uid == null) {
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final EntryPromptState state = await prepareEntryPrompt(
    bridge: ref.read(widgetBridgeProvider),
    flusher: ref.read(widgetLogFlushProvider),
    uid: uid,
    activityID: prompt.activityID,
  );
  if (!context.mounted || !messenger.mounted) {
    return;
  }
  switch (state) {
    case EntryPromptState.undone:
      showUndoBar(messenger, const TextSpan(text: entryUndoneNotice));
    case EntryPromptState.unsaved:
      showUndoBar(messenger, const TextSpan(text: entryUnsavedNotice));
    case EntryPromptState.ready:
      final Vice? vice = ref
          .read(viceListProvider)
          .value
          ?.where((Vice v) => v.id == prompt.viceID && !v.locked)
          .firstOrNull;
      if (vice == null) {
        showUndoBar(messenger, const TextSpan(text: entryHabitGoneNotice));
        return;
      }
      await askWhatWasGoingOn(
        context,
        ref,
        activityID: prompt.activityID,
        vice: vice,
      );
  }
}
