import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/dial_page.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/delete_with_undo.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';

class ViceActivityHistoryPage extends ConsumerStatefulWidget {
  const ViceActivityHistoryPage({super.key, required this.viceID});

  final String viceID;

  static const int pageSize = 50;
  static const String swipeHint =
      'Swipe an entry left to delete it. Tap it to edit.';
  static const String empty = 'Nothing logged for this habit yet';

  // The day heading: Today and Yesterday by name, then the date.
  static String dayLabel(DateTime day, DateTime today) =>
      switch (daysBetween(day, today)) {
        0 => 'Today',
        1 => 'Yesterday',
        _ => formatShortDay(day),
      };

  @override
  ConsumerState<ViceActivityHistoryPage> createState() =>
      _ViceActivityHistoryPageState();
}

class _ViceActivityHistoryPageState
    extends ConsumerState<ViceActivityHistoryPage> {
  int shown = ViceActivityHistoryPage.pageSize;
  // Asking for more starts a new query, which has no value until it loads;
  // until then the shorter list stays on screen instead of a spinner.
  ({String uid, List<ViceActivity> activities})? previous;
  // A dismissed row must leave the tree in the same frame, before the
  // snapshot without it arrives.
  final Set<String> dismissed = <String>{};
  // A row brought back gets a new key: the dismissed one may not have left
  // the tree yet when a refusal arrives.
  final Map<String, int> revived = <String, int>{};

  String get viceID => widget.viceID;

  final Set<String> archiving = <String>{};

  Future<void> _setArchived(Vice vice, {required bool archived}) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      archiving.add(vice.id);
    });

    String? message;
    try {
      if (!await ref
          .read(rejectedWritesProvider.notifier)
          .settle(
            ref
                .read(trackerWritesProvider)
                .setViceArchived(vice.id, archived: archived),
            '${archived ? 'Not archived' : 'Not unarchived'}: ${vice.name}',
          )) {
        message = queuedMessage;
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while archiving or unarchiving a habit');
      message =
          '${archived ? 'Could not archive' : 'Could not unarchive'} '
          '${vice.name}. ${firestoreErrorMessage(e)}';
    }

    if (mounted) {
      setState(() {
        archiving.remove(vice.id);
      });
    }
    if (message != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // The messenger is taken from this State, not the row, which is gone by
  // the time the server answers.
  void _delete(Vice vice, ViceActivity activity) {
    setState(() {
      dismissed.add(activity.id);
    });
    void show() {
      if (mounted) {
        setState(() {
          dismissed.remove(activity.id);
          revived.update(activity.id, (int n) => n + 1, ifAbsent: () => 1);
        });
      }
    }

    deleteWithUndo(
      ref,
      ScaffoldMessenger.of(context),
      vice,
      activity,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      onRestored: show,
      onFailed: show,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = ref.watch(userProvider).value?.uid;
    final AsyncValue<List<Vice>> viceListValue = ref.watch(viceListProvider);
    // One more than is shown, to learn whether there are older entries.
    final AsyncValue<List<ViceActivity>> loadedValue = ref.watch(
      viceActivityHistoryProvider((viceID: viceID, limit: shown + 1)),
    );

    if (viceListValue.error ?? loadedValue.error case final Object error) {
      return DialPage(
        title: 'History',
        children: <Widget>[
          SizedBox(
            height: 320,
            child: ErrorView(
              message: loadErrorMessage('this history', error),
              onRetry: () {
                ref.invalidate(viceListForUserProvider, asReload: true);
                ref.invalidate(
                  viceActivityHistoryForUserProvider,
                  asReload: true,
                );
              },
            ),
          ),
        ],
      );
    }

    final List<Vice>? viceList = viceListValue.value;
    final List<ViceActivity>? loaded = loadedValue.value;
    if (uid != null && loaded != null) {
      previous = (uid: uid, activities: loaded);
    }
    final List<ViceActivity>? fetched =
        loaded ?? (previous?.uid == uid ? previous?.activities : null);

    if (viceList == null || fetched == null) {
      return const DialPage(
        title: '',
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    final Vice? vice = viceList
        .where((Vice item) => item.id == viceID)
        .firstOrNull;

    if (vice == null) {
      return const DialPage(title: 'Habit not found', children: <Widget>[]);
    }

    final HabitMark mark = habitMarks(viceList)[vice.id] ?? const HabitMark(0);
    final bool hasOlder = fetched.length > shown;
    final List<ViceActivity> activityList =
        (hasOlder ? fetched.sublist(0, shown) : fetched)
            .where((ViceActivity a) => !dismissed.contains(a.id))
            .toList();
    final DateTime today = ref.watch(todayProvider);

    // Newest first, as the query orders them, so each day is one run.
    final List<(DateTime, List<ViceActivity>)> days =
        <(DateTime, List<ViceActivity>)>[];
    for (final ViceActivity activity in activityList) {
      final DateTime day = startOfDay(activity.createdAt.toDate());
      if (days.isEmpty || days.last.$1 != day) {
        days.add((day, <ViceActivity>[]));
      }
      days.last.$2.add(activity);
    }

    final ActivityCount? count = ref
        .watch(viceActivityCountProvider(vice.id))
        .value;

    return DialPage(
      title: vice.name,
      leading: HabitPip(mark: mark, size: 16),
      subtitle: <String>[
        vice.unit.nameFor(2),
        if (count != null) ManageData.countText(count),
        if (vice.archived) 'archived',
      ].join(' · '),
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleButton(
            icon: vice.archived ? DialGlyph.unarchive : DialGlyph.archive,
            tooltip: vice.archived ? 'Unarchive' : 'Archive',
            onPressed: archiving.contains(vice.id)
                ? null
                : () => _setArchived(vice, archived: !vice.archived),
          ),
          const SizedBox(width: DialSpace.xs),
          CircleButton(
            icon: DialGlyph.pencil,
            tooltip: 'Edit habit',
            onPressed: () {
              Navigator.of(context).pushNamed('/vices/${vice.id}/edit');
            },
          ),
        ],
      ),
      children: <Widget>[
        if (activityList.isEmpty)
          const PageFootnote(ViceActivityHistoryPage.empty)
        else ...<Widget>[
          for (final (DateTime day, List<ViceActivity> entries) in days) ...[
            SectionLabel(
              ViceActivityHistoryPage.dayLabel(day, today),
              trailing: vice.unit.label(
                entries.fold<int>(0, (int s, ViceActivity a) => s + a.quantity),
              ),
            ),
            DialCard(
              children: <Widget>[
                for (int i = 0; i < entries.length; i++) ...<Widget>[
                  if (i > 0) const CardDivider(indent: 56),
                  _row(vice, mark, entries[i]),
                ],
              ],
            ),
          ],
          if (hasOlder)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Center(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      shown += ViceActivityHistoryPage.pageSize;
                    });
                  },
                  child: const Text('Show older'),
                ),
              ),
            ),
          const PageFootnote(ViceActivityHistoryPage.swipeHint, center: true),
        ],
      ],
    );
  }

  Widget _row(Vice vice, HabitMark mark, ViceActivity activity) {
    final DialColors colors = DialColors.of(context);
    final ThemeData theme = Theme.of(context);
    final DateTime createdAt = activity.createdAt.toDate();
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);

    return Dismissible(
      key: ValueKey<(String, int)>((activity.id, revived[activity.id] ?? 0)),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(vice, activity),
      background: ColoredBox(
        color: theme.colorScheme.error,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 22),
            child: Icon(
              Icons.delete_outline,
              size: 22,
              color: theme.colorScheme.onError,
            ),
          ),
        ),
      ),
      child: Material(
        color: theme.cardTheme.color,
        child: InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).pushNamed('/vices/$viceID/activities/${activity.id}');
          },
          child: Semantics(
            label: formatDayAndTime(createdAt, alwaysUse24HourFormat: h24),
            excludeSemantics: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
                child: Row(
                  children: <Widget>[
                    SizedBox.square(
                      dimension: 30,
                      child: Center(
                        child: _EntryBead(
                          mark: mark,
                          pending: activity.pending,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                      child: Text(
                        formatTime(createdAt, alwaysUse24HourFormat: h24),
                        style: DialTypeScale.monoM.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          vice.unit.label(activity.quantity),
                          style: DialTypeScale.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (activity.pending)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                StrokeIcon(
                                  DialGlyph.cloudUp,
                                  size: 13,
                                  color: colors.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  NotSyncedMarker.defaultLabel,
                                  style: DialTypeScale.bodyS.copyWith(
                                    fontSize: 12,
                                    height: 1,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryBead extends StatelessWidget {
  const _EntryBead({required this.mark, required this.pending});

  final HabitMark mark;
  final bool pending;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: CustomPaint(
      painter: _EntryBeadPainter(mark, DialColors.of(context), pending),
    ),
  );
}

class _EntryBeadPainter extends CustomPainter {
  _EntryBeadPainter(this.mark, this.colors, this.pending);

  final HabitMark mark;
  final DialColors colors;
  final bool pending;

  @override
  void paint(Canvas canvas, Size size) => paintHabitMark(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 2,
    mark,
    colors,
    fill: pending ? 0 : 1,
    pending: pending,
  );

  @override
  bool shouldRepaint(_EntryBeadPainter old) =>
      old.mark != mark || old.colors != colors || old.pending != pending;
}
