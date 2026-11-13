import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

// Under a line in the amount on Insights: an offer to mark that amount a day
// as the habit's own line. Its state comes from the habit as stored, so every
// card on one habit agrees: no line, another line, or this one already.
class LineOffer extends ConsumerWidget {
  const LineOffer({super.key, required this.habitId, required this.cut});

  final String habitId;
  // The finding's amount a day, in the habit's unit.
  final double cut;

  static String offer(String habit, double cut) =>
      "Mark ${formatCount(cut)} a day as $habit's line";
  static String change(double cut) => 'Change it to ${formatCount(cut)} a day';
  static const String editHint = 'Change or remove it in Edit Habit.';
  static String offerNote(String habit) =>
      'Optional. Shown while $habit has no line. $editHint';
  static String current(String habit, HabitLine line, Vice vice) =>
      "$habit's line is ${line.words(vice.units)}.";
  static String saved(String habit, HabitLine line, Vice vice) =>
      "$habit's line: ${line.words(vice.units)}";

  static Vice? _live(ProviderContainer container, String id) => container
      .read(viceListProvider)
      .value
      ?.where((Vice v) => v.id == id)
      .firstOrNull;

  Future<void> _mark(BuildContext context, Vice vice, HabitLine line) async {
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TrackerWrites writes = container.read(trackerWritesProvider);
    // The line exists only sealed.
    if (!writes.canCreate) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Not saved. $noJournalKeyMessage')),
      );
      return;
    }
    final HabitLine? before = vice.line;
    final RejectedWrites rejected = container.read(
      rejectedWritesProvider.notifier,
    );

    Future<void> settle(SentWrite write) async {
      try {
        if (!await rejected.settle(
          write,
          "Change not saved: ${vice.name}'s line",
        )) {
          messenger.showSnackBar(const SnackBar(content: Text(queuedMessage)));
        }
      } on FirebaseException catch (e, stack) {
        reportError(e, stack, context: "while saving a habit's line");
        messenger.showSnackBar(
          SnackBar(content: Text('Not saved. ${firestoreErrorMessage(e)}')),
        );
      }
    }

    final SentWrite write = writes.updateVice(vice, line: (line: line));
    messenger.showSnackBar(
      SnackBar(
        content: Text(saved(vice.name, line, vice)),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final Vice? live = _live(container, vice.id);
            if (live == null || live.locked) return;
            settle(
              container
                  .read(trackerWritesProvider)
                  .updateVice(live, line: (line: before)),
            );
          },
        ),
      ),
    );
    await settle(write);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vice? vice = ref
        .watch(viceListProvider)
        .value
        ?.where((Vice v) => v.id == habitId)
        .firstOrNull;
    if (vice == null || vice.archived || vice.locked || cut <= 0) {
      return const SizedBox.shrink();
    }
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final HabitLine target = HabitLine(cut, LinePeriod.day);
    final HabitLine? now = vice.line;

    if (now == target) {
      return Text('${current(vice.name, now!, vice)} $editHint', style: small);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (now != null) ...<Widget>[
          Text(
            current(vice.name, now, vice),
            style: DialTypeScale.bodyS.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: DialSpace.xs),
        ],
        OutlinedButton(
          onPressed: () => _mark(context, vice, target),
          child: Text(now == null ? offer(vice.name, cut) : change(cut)),
        ),
        const SizedBox(height: DialSpace.xs),
        Text(
          now == null ? offerNote(vice.name) : 'Optional. $editHint',
          style: small,
        ),
      ],
    );
  }
}
