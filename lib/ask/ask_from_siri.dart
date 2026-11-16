import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/app_lock/app_lock.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/ask/ask_page.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/undo_bar.dart';

// AskQuestion in ios/Runner/AppShortcuts.swift keeps the question Siri or a
// shortcut gave until Dart takes it, and says when there is a new one.
class AskQuestionChannel {
  const AskQuestionChannel([
    this._channel = const MethodChannel('com.screendead.penchant/ask_question'),
  ]);

  final MethodChannel _channel;

  /// The question waiting to be asked, once: native forgets it.
  Future<String?> take() async {
    try {
      return await _channel.invokeMethod<String>('take');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while taking a question from Siri');
      return null;
    }
  }

  /// Called when native has a new question to [take]; null stops listening.
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

final askQuestionChannelProvider = Provider<AskQuestionChannel>(
  (ref) => const AskQuestionChannel(),
);

/// Only the iPhone app declares the intent.
final askFromSiriSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
);

/// The question Siri handed over, waiting for the app to be ready to ask it:
/// in memory only, dropped on sign-out and when another account signs in.
final pendingSiriQuestionProvider =
    NotifierProvider<PendingSiriQuestion, String?>(PendingSiriQuestion.new);

class PendingSiriQuestion extends Notifier<String?> {
  @override
  String? build() {
    // Not a watch: at a cold launch the question can come before Auth
    // restores the session, and that first uid must not drop it.
    ref.listen<String?>(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
      (String? before, String? after) {
        if (before != null && before != after) state = null;
      },
    );
    return null;
  }

  void request(String question) {
    final String q = question.trim();
    if (q.isEmpty || q.length > CallableAskJournal.maxQuestion) return;
    // Nobody is signed in: whoever signs in next may not be who asked.
    final AsyncValue<User?> user = ref.read(userProvider);
    if (user.hasValue && !user.isLoading && user.value == null) return;
    state = q;
  }

  void clear() => state = null;
}

/// Where a question from Siri goes once the app can act on it.
enum SiriAskOutcome {
  /// Asked on the Ask page, as if typed.
  ask,

  /// Settings, to turn on "Ask your journal".
  turnOn,

  /// Account Settings, to add and verify an email address.
  verifyEmail,

  /// An emulator build, which has no service to ask.
  noService,
}

typedef SiriQuestion = ({String question, SiriAskOutcome outcome});

/// The pending question once someone is signed in, the app is past its lock
/// and the journal key, the habits have loaded opened with it, and whether
/// asking is allowed is known; null until then.
final siriQuestionReadyProvider = Provider<SiriQuestion?>((Ref ref) {
  final String? question = ref.watch(pendingSiriQuestionProvider);
  if (question == null || ref.watch(userProvider).value == null) return null;
  if (ref.watch(appLockProvider).covered) return null;
  if (ref.watch(journalKeyPendingProvider) ||
      ref.watch(journalNeedsRecoveryKeyProvider) ||
      ref.watch(sealerProvider) == null) {
    return null;
  }
  final AsyncValue<List<Vice>> vices = ref.watch(viceListProvider);
  if (!vices.hasValue || vices.isLoading) return null;
  SiriQuestion to(SiriAskOutcome outcome) =>
      (question: question, outcome: outcome);
  if (ref.watch(askJournalProvider) != null) return to(SiriAskOutcome.ask);
  if (useFirebaseEmulators) return to(SiriAskOutcome.noService);
  // Until the profile and the saved switch are read, both look like no.
  if (!ref.watch(userProfileProvider).hasValue) return null;
  if (!ref.watch(claudeAllowedProvider)) return to(SiriAskOutcome.verifyEmail);
  if (!ref.watch(askJournalChoiceReadProvider).hasValue) return null;
  return to(SiriAskOutcome.turnOn);
});

/// Takes a question the launch came with and hears later ones, for the life
/// of the app; MyApp keeps it alive.
final askQuestionListenerProvider = Provider<void>((ref) {
  if (!ref.watch(askFromSiriSupportedProvider)) return;
  final AskQuestionChannel channel = ref.watch(askQuestionChannelProvider);
  bool disposed = false;
  Future<void> take() async {
    final String? question = await channel.take();
    if (question != null && !disposed) {
      ref.read(pendingSiriQuestionProvider.notifier).request(question);
    }
  }

  channel.onChanged(() => unawaited(take()));
  ref.onDispose(() {
    disposed = true;
    channel.onChanged(null);
  });
  unawaited(take());
});

const String siriTurnOnNotice =
    'To ask from Siri, turn on “Ask your journal” here first. Nothing was '
    'sent.';
const String siriVerifyNotice =
    'To ask from Siri, add and verify an email address first. Nothing was '
    'sent.';
const String siriNoServiceNotice =
    'This build has no service to ask. Nothing was sent.';

/// Today's handling of a ready question. The Ask page asks it itself
/// ([AskPage] listens to [siriQuestionReadyProvider]), so here it is only
/// brought to the top, or opened: popping an open Ask page would drop a
/// question it is still answering. Anything else drops the question, so
/// turning the switch on later sends nothing, and says why.
void openSiriQuestion(
  NavigatorState navigator,
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  SiriQuestion question,
) {
  if (question.outcome == SiriAskOutcome.ask) {
    bool open = false;
    navigator.popUntil((Route<dynamic> r) {
      open = r.settings.name == AskPage.route;
      return open || r.isFirst;
    });
    if (!open) navigator.pushNamed(AskPage.route);
    return;
  }
  ref.read(pendingSiriQuestionProvider.notifier).clear();
  navigator.popUntil((Route<dynamic> r) => r.isFirst);
  switch (question.outcome) {
    case SiriAskOutcome.turnOn:
      navigator.pushNamed('/settings');
      showUndoBar(messenger, const TextSpan(text: siriTurnOnNotice));
    case SiriAskOutcome.verifyEmail:
      navigator.pushNamed('/settings/account');
      showUndoBar(messenger, const TextSpan(text: siriVerifyNotice));
    case SiriAskOutcome.noService:
      showUndoBar(messenger, const TextSpan(text: siriNoServiceNotice));
    case SiriAskOutcome.ask:
      break;
  }
}
