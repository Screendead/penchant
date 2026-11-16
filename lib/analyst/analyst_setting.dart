import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/analyst/investigation.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device may investigate questions with Claude, each time only
/// after asking: off until the person turns it on in Settings, kept on this
/// device only, and of no effect while Ask your journal is off.
final analystEnabledProvider = NotifierProvider<AnalystEnabled, bool>(
  AnalystEnabled.new,
);

class AnalystEnabled extends Notifier<bool> {
  static const String key = 'analyst';

  bool _chosen = false;

  @override
  bool build() {
    _load();
    return false;
  }

  // A failed read leaves it off.
  Future<void> _load() async {
    final bool? saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = prefs.getBool(key);
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the analyst choice');
      return;
    }
    // A choice made while the read was in flight is newer than what it read.
    if (saved != null && !_chosen) {
      state = saved;
    }
  }

  Future<void> choose(bool on) async {
    _chosen = true;
    state = on;
    // A failed save still applies the choice until the app closes.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, on);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the analyst choice');
    }
  }
}

/// Null while investigating is switched off or cannot work here (Ask off,
/// signed out, an emulator build, a guest or an unverified email).
final Provider<Investigator?> investigatorProvider = Provider<Investigator?>((
  Ref ref,
) {
  // The function exists only in production, which a flagged build must never
  // reach.
  if (useFirebaseEmulators) return null;
  if (!ref.watch(askJournalEnabledProvider)) return null;
  if (!ref.watch(analystEnabledProvider)) return null;
  if (ref.watch(userProvider).value == null) return null;
  if (!ref.watch(claudeAllowedProvider)) return null;
  return CallableInvestigator(_callInvestigate);
});

Future<Object?> _callInvestigate(Map<String, Object?> data) =>
    callClaude('investigate', CallableInvestigator.timeout, data);

/// The `investigate` Cloud Function (functions/analyst.js), through [call],
/// which answers `{step, reason}`.
class CallableInvestigator implements Investigator {
  CallableInvestigator(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  /// Past the function's 120 s, so its own answer arrives first.
  static const Duration timeout = Duration(seconds: 130);

  @override
  Future<InvestigationStep> step(Map<String, Object?> request) async {
    final Object? answer;
    try {
      answer = await call(request);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw const InvestigateFailed('daily_cap');
      }
      rethrow;
    }
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason != 'ok') {
      throw InvestigateFailed(reason is String ? reason : 'unparsable');
    }
    final InvestigationStep? step = parseStep((answer as Map)['step']);
    if (step == null) throw const InvestigateFailed('invalid');
    return step;
  }
}

/// What each investigation sends, said before it starts; [AnalystSetting]
/// says it once more when turned on.
const String analystSends =
    'This time the results of its queries are sent to Penchant’s server and '
    'on to Anthropic’s Claude Opus with your question and habit names and '
    'units: counts, amounts, totals, dates, times, urge ratings, prices, '
    'how each entry was logged, tag names and habit names. Note text, '
    'day-note text and tags in your own words are never sent; the '
    'database refuses to read them. Anthropic does not use it for training '
    'and deletes it within 30 days.';

/// Asks before one investigation of [question]; true only on Yes.
Future<bool> confirmInvestigation(BuildContext context) async {
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AnalystSetting.confirmTitle),
      content: const Text(analystSends),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AnalystSetting.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AnalystSetting.yes),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// The Settings row for [analystEnabledProvider]. Turning it on first says
/// what an investigation sends and asks again; turning it off needs no
/// asking.
class AnalystSetting extends ConsumerWidget {
  const AnalystSetting({super.key});

  static const String label = 'Investigate';
  static const String subtitle =
      'Claude runs queries on this device to look into a question, asking '
      'you each time.';
  static const String needsAsk = 'Turn on “Ask your journal” first.';
  static const String disclosureTitle = 'Let Claude investigate?';
  static const String disclosure =
      'Each time you start an investigation, and only after you say yes, '
      'Claude writes queries that run on this device, reads what they find '
      'and writes a short account. $analystSends Nothing is stored: an '
      'investigation is kept in memory until the app closes or you sign out.';
  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';
  static const String confirmTitle = 'Investigate with Claude?';
  static const String yes = 'Yes, investigate';
  static const String cancel = 'Cancel';

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final AnalystEnabled notifier = ref.read(analystEnabledProvider.notifier);
    if (!on) {
      await notifier.choose(false);
      return;
    }
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(disclosureTitle),
        content: const Text(disclosure),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(notNow),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(turnOn),
          ),
        ],
      ),
    );
    if (agreed ?? false) await notifier.choose(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(claudeAllowedProvider)) {
      return const ClaudeNeedsEmailRow(label: label);
    }
    if (!ref.watch(askJournalEnabledProvider)) {
      return const MergeSemantics(
        child: CardRow(
          label: label,
          subtitle: needsAsk,
          trailing: Switch.adaptive(value: false, onChanged: null),
        ),
      );
    }
    final bool on = ref.watch(analystEnabledProvider);
    return MergeSemantics(
      child: CardRow(
        label: label,
        subtitle: subtitle,
        onTap: () => _set(context, ref, !on),
        trailing: Switch.adaptive(
          value: on,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: (bool value) => _set(context, ref, value),
        ),
      ),
    );
  }
}
