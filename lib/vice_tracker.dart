import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';

// Today: the day as a 24-hour dial, a tally for each habit with a + that logs
// one now, and the Log button and its fan.
class ViceTracker extends ConsumerStatefulWidget {
  const ViceTracker({super.key});

  static const String noHabits =
      'No habits yet. Add one from Manage Data in the menu.';

  // Room below the content for the Log button, and for the bar above it.
  static const double logClearance = DialSize.logButton + 6 + DialSpace.m;

  @override
  ConsumerState<ViceTracker> createState() => _ViceTrackerState();
}

class _ViceTrackerState extends ConsumerState<ViceTracker> {
  static const String _storageID = 'ViceTracker.pinnedDay';

  // Null follows today, so the tab moves on at midnight.
  DateTime? pinnedDay;

  @override
  void initState() {
    super.initState();
    pinnedDay =
        PageStorage.maybeOf(context)?.readState(context, identifier: _storageID)
            as DateTime?;
  }

  void _selectDay(DateTime day) {
    final DateTime today = ref.read(todayProvider);
    final DateTime? pinned = day.isBefore(today) ? day : null;
    setState(() {
      pinnedDay = pinned;
    });
    PageStorage.maybeOf(
      context,
    )?.writeState(context, pinned, identifier: _storageID);
  }

  // A log is always now, so a past day gives way to today to show it.
  void _log(Vice vice, Offset from) {
    if (pinnedDay != null) {
      _selectDay(ref.read(todayProvider));
    }
    logOne(
      ref,
      ScaffoldMessenger.of(context),
      vice,
      from: from,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      bottomClearance: ViceTracker.logClearance,
    );
  }

  void _record(Vice? vice) {
    showDialog<void>(
      context: context,
      builder: (_) => RecordNewActivityDialog(initialViceID: vice?.id),
    );
  }

  void _openEntry(DialEntry entry) {
    Navigator.of(
      context,
    ).pushNamed('/vices/${entry.vice.id}/activities/${entry.id}');
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = ref.watch(todayProvider);
    final DateTime selected = pinnedDay ?? today;
    final DateTime day = selected.isAfter(today) ? today : selected;

    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final List<Vice>? allVices = ref.watch(viceListProvider).value;
    final AsyncValue<List<ViceActivity>> activitiesValue = ref.watch(
      viceActivityDayProvider(day),
    );
    final List<Vice>? vices = vicesValue.value;

    // With no habits there is nothing to draw, whatever the day's query did.
    if (!vicesValue.hasError && vices != null && vices.isEmpty) {
      return const InfoBox(message: ViceTracker.noHabits);
    }

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(
        message: loadErrorMessage('this day', error),
        isError: true,
        onRetry: () {
          ref.invalidate(viceListForUserProvider, asReload: true);
          ref.invalidate(viceActivityDayForUserProvider, asReload: true);
        },
      );
    }

    final Map<String, HabitMark> marks = habitMarks(
      allVices ?? vices ?? const <Vice>[],
    );
    HabitMark markOf(Vice vice) => marks[vice.id] ?? const HabitMark(0);
    final List<ViceActivity>? activities = activitiesValue.value;
    final Map<String, Vice> byID = <String, Vice>{
      for (final Vice vice in vices ?? const <Vice>[]) vice.id: vice,
    };
    // Archived habits' entries stay off Today, as do those of a habit gone.
    final List<DialEntry>? entries = vices == null || activities == null
        ? null
        : <DialEntry>[
            for (final ViceActivity a in activities)
              if (byID[a.viceID] case final Vice vice)
                DialEntry(
                  id: a.id,
                  vice: vice,
                  mark: markOf(vice),
                  quantity: a.quantity,
                  at: a.createdAt.toDate(),
                  pending: a.pending,
                ),
          ];
    final Map<String, int> totals = <String, int>{
      for (final Vice vice in vices ?? const <Vice>[]) vice.id: 0,
    };
    for (final DialEntry e in entries ?? const <DialEntry>[]) {
      totals[e.vice.id] = totals[e.vice.id]! + e.quantity;
    }
    final bool offline = ref.watch(offlineProvider).value ?? false;
    final String? summary = entries == null
        ? null
        : DayDial.summary(
            day,
            today,
            vices!,
            <int>[for (final Vice v in vices) totals[v.id]!],
            <DateTime>[for (final DialEntry e in entries) e.at],
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final DialColors colors = DialColors.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = min(constraints.maxWidth, 600.0);
        final double side = min(
          DialSize.dialDiameter,
          width - 2 * DialSpace.gutter,
        );

        return Stack(
          children: <Widget>[
            Center(
              child: SizedBox(
                width: width,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    DialSpace.m,
                    DialSpace.xs,
                    DialSpace.m,
                    ViceTracker.logClearance + DialSpace.xl,
                  ),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DialSpace.gutter - DialSpace.m,
                      ),
                      child: DayPicker(
                        day: day,
                        today: today,
                        onSelect: _selectDay,
                        habits: vices ?? const <Vice>[],
                        marks: marks,
                      ),
                    ),
                    const SizedBox(height: DialSpace.s),
                    Center(
                      child: SizedBox.square(
                        dimension: side,
                        child: DayDial(
                          day: day,
                          today: today,
                          entries: entries,
                          semanticsLabel: summary,
                          offline: offline,
                          onBeadTap: _openEntry,
                          onSwipe: (int days) => _selectDay(
                            DateTime(day.year, day.month, day.day + days),
                          ),
                        ),
                      ),
                    ),
                    if (offline && entries != null && entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: DialSpace.xs),
                        child: Text(
                          ClearDay.offlineBody,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.clearInk),
                        ),
                      ),
                    PendingDayNote(selectedDate: day),
                    if (vices == null)
                      const Padding(
                        padding: EdgeInsets.all(DialSpace.m),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      for (final Vice vice in vices)
                        TallyRow(
                          key: ValueKey<String>('tally-${vice.id}'),
                          vice: vice,
                          mark: markOf(vice),
                          total: entries == null ? null : totals[vice.id],
                          day: day,
                          onLog: (Offset from) => _log(vice, from),
                        ),
                  ],
                ),
              ),
            ),
            if (vices != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: DialSpace.m,
                child: Center(
                  child: LogButton(
                    habits: <FanHabit>[
                      for (final Vice vice in vices)
                        (vice: vice, mark: markOf(vice)),
                    ],
                    onLog: _log,
                    onRecord: _record,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
