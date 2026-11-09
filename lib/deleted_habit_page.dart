import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/deleted_habit_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/dial_page.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

/// The entries of a habit that no longer exists. They cannot be restored once
/// deleted (the rules refuse an entry whose habit the writer does not own), so
/// each delete is confirmed on the page instead of offering Undo.
class DeletedHabitPage extends ConsumerStatefulWidget {
  const DeletedHabitPage({super.key});

  static const String route = '/deleted-habit';
  static const String title = 'Deleted habit';
  static const String about =
      'These entries belong to a habit that no longer exists, so no other '
      'screen shows them. Export my data, under Settings, Account, includes '
      'them. Deleted entries cannot be restored.';
  static const String empty = 'No entries left';
  static const String deleteAll = 'Delete all';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String deleteEntry = 'Delete entry';
  static const String confirmOne = 'Delete this entry?';

  static String entries(int count) =>
      '${formatCount(count)} ${pluralWord(count, one: 'entry', other: 'entries')}';

  static String confirmAll(int count) =>
      'Delete ${entries(count)}? This cannot be undone.';

  static String deleted(int count) => 'Deleted ${entries(count)}';

  static String failed(int count, FirebaseException e) =>
      'Could not delete ${entries(count)}. ${firestoreErrorMessage(e)}';

  @override
  ConsumerState<DeletedHabitPage> createState() => _DeletedHabitPageState();
}

class _DeletedHabitPageState extends ConsumerState<DeletedHabitPage> {
  int shown = ViceActivityHistoryPage.pageSize;
  // Deleted here and not yet re-read; the page reads once, so they stay
  // hidden unless the server refuses the delete.
  final Set<String> gone = <String>{};
  // The entry whose delete awaits confirmation, or [_all].
  String? confirming;
  static const String _all = '';

  Future<void> _delete(List<ViceActivity> activities) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    setState(() {
      confirming = null;
      gone.addAll(activities.map((ViceActivity a) => a.id));
    });

    bool queued = false;
    final List<ViceActivity> refused = <ViceActivity>[];
    FirebaseException? error;
    await Future.wait(<Future<void>>[
      for (final ViceActivity activity in activities)
        () async {
          try {
            if (!await rejected.settle(
              writes.deleteActivity(activity.id),
              'Not deleted: ${describeActivity(DeletedHabitPage.title, Unit.fallback, activity.measure, activity.createdAt.toDate(), alwaysUse24HourFormat: h24)}',
            )) {
              queued = true;
            }
          } on FirebaseException catch (e, stack) {
            reportError(e, stack, context: 'while deleting an orphan entry');
            refused.add(activity);
            error = e;
          }
        }(),
    ]);

    if (mounted && refused.isNotEmpty) {
      setState(() {
        gone.removeAll(refused.map((ViceActivity a) => a.id));
      });
    }
    if (!messenger.mounted) return;
    final FirebaseException? failure = error;
    showUndoBar(
      messenger,
      TextSpan(
        text: failure != null
            ? DeletedHabitPage.failed(refused.length, failure)
            : queued
            ? queuedDeleteMessage
            : DeletedHabitPage.deleted(activities.length),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = ref.watch(todayProvider);
    final AsyncValue<List<ViceActivity>> value = ref.watch(
      deletedHabitActivitiesProvider,
    );

    if (value.error case final Object error) {
      return DialPage(
        title: DeletedHabitPage.title,
        children: <Widget>[
          SizedBox(
            height: 320,
            child: ErrorView(
              message: loadErrorMessage('these entries', error),
              onRetry: () {
                ref.invalidate(viceListForUserProvider, asReload: true);
                ref.invalidate(
                  deletedHabitActivitiesForUserProvider,
                  asReload: true,
                );
              },
            ),
          ),
        ],
      );
    }

    final List<ViceActivity>? loaded = value.value;
    if (loaded == null) {
      return const DialPage(
        title: DeletedHabitPage.title,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    final List<ViceActivity> left = <ViceActivity>[
      for (final ViceActivity a in loaded)
        if (!gone.contains(a.id)) a,
    ];
    final bool hasOlder = left.length > shown;
    final List<ViceActivity> page = hasOlder ? left.sublist(0, shown) : left;
    final List<(DateTime, List<ViceActivity>)> days =
        <(DateTime, List<ViceActivity>)>[];
    for (final ViceActivity activity in page) {
      final DateTime day = startOfDay(activity.createdAt.toDate());
      if (days.isEmpty || days.last.$1 != day) {
        days.add((day, <ViceActivity>[]));
      }
      days.last.$2.add(activity);
    }

    return DialPage(
      title: DeletedHabitPage.title,
      leading: const DeletedHabitPip(size: 16),
      subtitle: DeletedHabitPage.entries(left.length),
      children: <Widget>[
        const PageFootnote(DeletedHabitPage.about),
        if (left.isEmpty)
          const PageFootnote(DeletedHabitPage.empty)
        else ...<Widget>[
          const SizedBox(height: DialSpace.l),
          DialCard(
            children: <Widget>[
              if (confirming == _all)
                _Confirm(
                  text: DeletedHabitPage.confirmAll(left.length),
                  onCancel: () => setState(() => confirming = null),
                  onDelete: () => _delete(left),
                )
              else
                _DeleteAllRow(onTap: () => setState(() => confirming = _all)),
            ],
          ),
          for (final (DateTime day, List<ViceActivity> entries) in days) ...[
            SectionLabel(
              ViceActivityHistoryPage.dayLabel(day, today),
              trailing: formatCount(
                entries.fold<num>(0, (num s, ViceActivity a) => s + a.measure),
              ),
            ),
            DialCard(
              children: <Widget>[
                for (int i = 0; i < entries.length; i++) ...<Widget>[
                  if (i > 0) const CardDivider(indent: 56),
                  if (confirming == entries[i].id)
                    _Confirm(
                      text: DeletedHabitPage.confirmOne,
                      onCancel: () => setState(() => confirming = null),
                      onDelete: () => _delete(<ViceActivity>[entries[i]]),
                    )
                  else
                    _row(entries[i]),
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
        ],
      ],
    );
  }

  Widget _row(ViceActivity activity) {
    final DialColors colors = DialColors.of(context);
    final ThemeData theme = Theme.of(context);
    final DateTime createdAt = activity.createdAt.toDate();
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: <Widget>[
            const SizedBox.square(
              dimension: 30,
              child: Center(child: DeletedHabitPip(size: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MergeSemantics(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Semantics(
                            label: formatDayAndTime(
                              createdAt,
                              alwaysUse24HourFormat: h24,
                            ),
                            child: ExcludeSemantics(
                              child: Text(
                                formatTime(
                                  createdAt,
                                  alwaysUse24HourFormat: h24,
                                ),
                                style: DialTypeScale.monoM.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                          if (activity.triggers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                activity.triggers
                                    .map(triggerShortDisplay)
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DialTypeScale.bodyS.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatCount(activity.measure),
                      style: DialTypeScale.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: DeletedHabitPage.deleteEntry,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Icon(Icons.delete_outline, size: 20, color: colors.muted),
              onPressed: () => setState(() => confirming = activity.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAllRow extends StatelessWidget {
  const _DeleteAllRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.delete_outline, size: 20, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  DeletedHabitPage.deleteAll,
                  style: DialTypeScale.bodyL.copyWith(
                    height: 1.2,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The in-page confirmation that stands in a row's place.
class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.text,
    required this.onCancel,
    required this.onDelete,
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const ButtonStyle tall = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(Size(64, 44)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: DialTypeScale.body.copyWith(color: scheme.onSurface),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                style: tall,
                onPressed: onCancel,
                child: const Text(DeletedHabitPage.cancel),
              ),
              TextButton(
                style: tall.merge(
                  TextButton.styleFrom(foregroundColor: scheme.error),
                ),
                onPressed: onDelete,
                child: const Text(DeletedHabitPage.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A deleted habit has no colour: a muted dashed ring.
class DeletedHabitPip extends StatelessWidget {
  const DeletedHabitPip({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _RingPainter(DialColors.of(context).muted)),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Rect rect = (Offset.zero & size).deflate(paint.strokeWidth / 2);
    const int dashes = 8;
    const double sweep = 2 * 3.141592653589793 / dashes;
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
