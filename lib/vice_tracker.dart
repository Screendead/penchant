import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/guest_expiry.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/app_menu_bar.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/guest_expiry_banner.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';

// Today: the day as a 24-hour dial, a tally for each habit with a + that logs
// one now, the Trends sheet peeking below them, and the Log button and its fan
// docked on the sheet's edge.
class ViceTracker extends ConsumerStatefulWidget {
  const ViceTracker({super.key});

  static const String noHabits =
      'No habits yet. Add one from Habits in the menu.';

  // From this width Today and Trends sit side by side, Trends as a pane.
  static const double splitWidth = 900;

  // Room below a snackbar for the Log button: on the sheet's peek, or at the
  // foot of Today's column in the split view.
  static double logClearance(BuildContext context, {bool split = false}) =>
      split
      ? _splitLogInset(context) + DialSize.logButton + DialSpace.xs
      : TrendsSheet.peekHeight(context) +
            DialSize.logButton / 2 +
            6 +
            DialSpace.xs;

  static double _splitLogInset(BuildContext context) =>
      max(DialSpace.m, MediaQuery.paddingOf(context).bottom);

  // Today's column in the split view.
  static double splitColumnWidth(double width) =>
      (width * 0.42).clamp(400.0, 560.0);

  @override
  ConsumerState<ViceTracker> createState() => _ViceTrackerState();
}

class _ViceTrackerState extends ConsumerState<ViceTracker> {
  static const String _storageID = 'ViceTracker.pinnedDay';

  // Null follows today, so the tab moves on at midnight.
  DateTime? pinnedDay;

  // Whether the last layout was the split view.
  bool _split = false;

  final DraggableScrollableController _sheet = DraggableScrollableController();
  late final SheetPosition _position = SheetPosition(_sheet);

  late final TodayLogTarget _logTarget = ref.read(todayLogTargetProvider);

  @override
  void initState() {
    super.initState();
    _logTarget.log = _logNow;
    pinnedDay =
        PageStorage.maybeOf(context)?.readState(context, identifier: _storageID)
            as DateTime?;
    ref.listenManual<int?>(
      guestDaysLeftProvider,
      (int? _, int? days) => _warnGuest(days),
      fireImmediately: true,
    );
  }

  // After the frame: it may fire from initState, where no provider may change.
  void _warnGuest(int? days) {
    if (days == null || days > GuestExpiry.sheetDays) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final DateTime today = ref.read(todayProvider);
      if (ref.read(guestSheetShownProvider) == today) {
        return;
      }
      ref.read(guestSheetShownProvider.notifier).shownOn(today);
      unawaited(showGuestExpirySheet(context, days));
    });
  }

  @override
  void dispose() {
    if (_logTarget.log == _logNow) {
      _logTarget.log = null;
    }
    _position.dispose();
    _sheet.dispose();
    super.dispose();
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

  // From the day shown now, not the one last built, so keys pressed within a
  // frame each count.
  void _stepDay(int days) {
    final DateTime today = ref.read(todayProvider);
    final DateTime shown = pinnedDay ?? today;
    _selectDay(addDays(shown.isAfter(today) ? today : shown, days));
  }

  // A log is always now, so a past day gives way to today to show it.
  void _log(Vice vice, Offset? from) {
    if (pinnedDay != null) {
      _selectDay(ref.read(todayProvider));
    }
    logOne(
      ref,
      ScaffoldMessenger.of(context),
      vice,
      from: from,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      bottomClearance: ViceTracker.logClearance(context, split: _split),
    );
  }

  // From a key or the menu bar, which have no bead to fly in.
  void _logNow(Vice vice) => _log(vice, null);

  void _record(Vice? vice) {
    RecordNewActivityDialog.show(
      context,
      initialViceID: vice?.id,
      bottomClearance: ViceTracker.logClearance(context, split: _split),
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
    final List<Vice>? listed = vicesValue.value;

    // With no habits there is nothing to draw, whatever the day's query did;
    // archived ones still open in Trends.
    final bool noHabits =
        !vicesValue.hasError && listed != null && listed.isEmpty;
    if (noHabits && (allVices == null || allVices.isEmpty)) {
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
      allVices ?? listed ?? const <Vice>[],
    );
    HabitMark markOf(Vice vice) => marks[vice.id] ?? const HabitMark(0);
    final List<Vice>? vices = listed == null ? null : tallyOrder(listed, marks);
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
                  quantity: a.measure,
                  at: a.createdAt.toDate(),
                  pending: a.pending,
                ),
          ];
    final Map<String, num> totals = <String, num>{
      for (final Vice vice in vices ?? const <Vice>[]) vice.id: 0,
    };
    for (final DialEntry e in entries ?? const <DialEntry>[]) {
      totals[e.vice.id] = totals[e.vice.id]! + e.quantity;
    }
    final bool offline = ref.watch(offlineProvider).value ?? false;
    final int? guestDaysLeft = ref.watch(guestDaysLeftProvider);
    final Widget? guestBanner =
        guestDaysLeft == null || guestDaysLeft > GuestExpiry.bannerDays
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: DialSpace.xs),
            child: GuestExpiryBanner(daysLeft: guestDaysLeft),
          );
    final Map<String, double> storedTypicals = ref.watch(
      storedTypicalsProvider,
    );
    final String? summary = entries == null
        ? null
        : DayDial.summary(
            day,
            today,
            vices!,
            <num>[for (final Vice v in vices) totals[v.id]!],
            <DateTime>[for (final DialEntry e in entries) e.at],
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final DialColors colors = DialColors.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool split = constraints.maxWidth >= ViceTracker.splitWidth;
        _split = split;
        final double column = split
            ? ViceTracker.splitColumnWidth(constraints.maxWidth)
            : constraints.maxWidth;
        // A phone on its side keeps the notch's side of Today clear.
        final double notch = split ? MediaQuery.paddingOf(context).left : 0;
        final double width = min(column - notch, 600.0);
        final double side = min(
          DialSize.dialDiameter,
          width - 2 * DialSpace.gutter,
        );

        final double height = constraints.maxHeight;
        final double peek = TrendsSheet.peekHeight(context);
        final double minSize = min(0.5, peek / height);
        final double logInset = ViceTracker._splitLogInset(context);
        final Widget page = noHabits
            ? Padding(
                padding: const EdgeInsets.all(DialSpace.m),
                child: Column(
                  children: <Widget>[
                    ?guestBanner,
                    const Expanded(
                      child: InfoBox(message: ViceTracker.noHabits),
                    ),
                  ],
                ),
              )
            : Center(
                child: SizedBox(
                  width: width,
                  child: ListView(
                    // The mock-up's spacing: 6 above the day row and the
                    // dial, 10 above the tallies.
                    padding: EdgeInsets.fromLTRB(
                      DialSpace.m,
                      6,
                      DialSpace.m,
                      split
                          ? logInset + DialSize.logButton + DialSpace.m
                          : DialSize.logButton / 2 + 6 + DialSpace.m,
                    ),
                    children: <Widget>[
                      ?guestBanner,
                      const RecoveryKeyCard(),
                      // The arrows' 40 pt circles sit 20 from the edges, their
                      // 44 pt targets 18.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: DayPicker(
                          day: day,
                          today: today,
                          onSelect: _selectDay,
                          habits: vices ?? const <Vice>[],
                          marks: marks,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: SizedBox.square(
                          dimension: side,
                          child: DayDial(
                            day: day,
                            today: today,
                            entries: entries,
                            semanticsLabel: summary,
                            offline: offline,
                            storedTypicals: storedTypicals,
                            onBeadTap: _openEntry,
                            onSwipe: (int days) =>
                                _selectDay(addDays(day, days)),
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
                      const SizedBox(height: 10),
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
              );

        // Left and Right step through days: anywhere in the split view but
        // the chart, which takes them for its cursor, and on Today alone
        // under the sheet. Nothing has focus at launch, so Today takes it.
        // Cmd-1 to Cmd-9 log one of the habit in that place; on macOS the Log
        // menu has the same keys, and takes them when focus is elsewhere.
        final int back = Directionality.of(context) == TextDirection.rtl
            ? 1
            : -1;
        Widget dayKeys(Widget child) => CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _stepDay(back),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _stepDay(-back),
            for (final (int i, Vice vice)
                in (vices ?? const <Vice>[]).indexed.take(habitKeyCount))
              habitKey(i): () => _logNow(vice),
          },
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            debugLabel: 'Today',
            child: child,
          ),
        );
        final Widget? logButton = vices == null || vices.isEmpty
            ? null
            : LogButton(
                habits: <FanHabit>[
                  for (final Vice vice in vices)
                    (vice: vice, mark: markOf(vice)),
                ],
                onLog: _log,
                onRecord: _record,
              );

        if (split) {
          return dayKeys(
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: column,
                  padding: EdgeInsets.only(left: notch),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: page),
                      if (logButton != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: logInset,
                          child: Center(child: logButton),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: allVices == null || allVices.isEmpty
                      ? const SizedBox.shrink()
                      : TrendsSheet.pane(
                          habits: trendsOrder(allVices, marks),
                          marks: marks,
                          onOpenDay: _selectDay,
                        ),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: <Widget>[
            // Today ends where the peek starts, so nothing hides under it.
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: peek,
              // Covered by the open sheet, Today takes no keyboard focus.
              child: ListenableBuilder(
                listenable: _position,
                builder: (BuildContext context, Widget? child) => ExcludeFocus(
                  excluding: TrendsSheet.openness(_sheet, minSize) > 0.9,
                  child: child!,
                ),
                child: dayKeys(page),
              ),
            ),
            ListenableBuilder(
              listenable: _position,
              builder: (BuildContext context, Widget? child) {
                final double p = TrendsSheet.openness(_sheet, minSize);
                if (p <= 0) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onTap: () => unawaited(
                        TrendsSheet.moveTo(context, _sheet, minSize),
                      ),
                      child: ColoredBox(
                        color: colors.scrim.withValues(
                          alpha: colors.scrim.a * p,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (allVices != null && allVices.isNotEmpty)
              ListenableBuilder(
                listenable: _position,
                builder: (BuildContext context, Widget? child) =>
                    BlockSemantics(
                      blocking: TrendsSheet.openness(_sheet, minSize) > 0.9,
                      child: child,
                    ),
                child: TrendsSheet(
                  controller: _sheet,
                  minSize: minSize,
                  habits: trendsOrder(allVices, marks),
                  marks: marks,
                ),
              ),
            if (logButton != null)
              ListenableBuilder(
                listenable: _position,
                builder: (BuildContext context, Widget? child) {
                  final double size = _sheet.isAttached ? _sheet.size : minSize;
                  // The button rides the sheet's edge and shrinks away as it
                  // opens, gone by a quarter of the way.
                  final double shown =
                      (1 - TrendsSheet.openness(_sheet, minSize) * 4).clamp(
                        0.0,
                        1.0,
                      );
                  return Positioned(
                    left: 0,
                    right: 0,
                    top: height * (1 - size) - DialSize.logButton / 2,
                    child: IgnorePointer(
                      ignoring: shown < 0.5,
                      child: ExcludeFocus(
                        excluding: shown < 0.5,
                        child: ExcludeSemantics(
                          excluding: shown < 0.5,
                          child: Opacity(
                            opacity: shown,
                            child: Transform.scale(
                              scale: 0.6 + 0.4 * shown,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: Center(child: logButton),
              ),
          ],
        );
      },
    );
  }
}

// Trends lists the habits in use first, then the archived ones, each oldest
// first, so the default (the first) is never archived while one is in use.
List<Vice> trendsOrder(List<Vice> vices, Map<String, HabitMark> marks) {
  int order(Vice a, Vice b) => (marks[a.id]?.creationIndex ?? 0).compareTo(
    marks[b.id]?.creationIndex ?? 0,
  );
  return <Vice>[
    ...vices.where((Vice v) => !v.archived).toList()..sort(order),
    ...vices.where((Vice v) => v.archived).toList()..sort(order),
  ];
}
