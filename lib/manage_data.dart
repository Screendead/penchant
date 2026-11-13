import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/deleted_habit_page.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/deleted_habit_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/dial_page.dart';
import 'package:tracker/widgets/info_box.dart';

class ManageData extends ConsumerStatefulWidget {
  const ManageData({super.key});

  static const String title = 'Habits';
  static const String archivedLabel = 'Archived';
  static const String colourNote =
      'Colours follow the order habits were added, archived ones included. '
      'From the sixth habit on, the five colours repeat as rings.';
  static const String countUnavailable = 'Count unavailable';
  static const String deletedHabitNote = 'Their habit no longer exists';

  static String countText(ActivityCount count) {
    final String activities =
        '${formatCount(count.count)} '
        '${pluralWord(count.count, one: 'entry', other: 'entries')}';
    return switch (count.source) {
      CountSource.server => activities,
      CountSource.deviceOffline => '$activities on this device (offline)',
      CountSource.deviceServerFailed =>
        '$activities on this device (server count unavailable)',
    };
  }

  @override
  ConsumerState<ManageData> createState() => _ManageDataState();
}

class _ManageDataState extends ConsumerState<ManageData> {
  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Vice>> viceListValue = ref.watch(viceListProvider);
    final List<Vice>? viceList = viceListValue.value;
    final List<Vice> active = <Vice>[
      for (final Vice vice in viceList ?? const <Vice>[])
        if (!vice.archived) vice,
    ];
    final List<Vice> archived = <Vice>[
      for (final Vice vice in viceList ?? const <Vice>[])
        if (vice.archived) vice,
    ];
    final Map<String, HabitMark> marks = habitMarks(viceList ?? const <Vice>[]);
    final int? orphans = ref.watch(deletedHabitCountProvider);

    return DialPage(
      title: ManageData.title,
      subtitle: viceList == null || viceListValue.hasError
          ? null
          : '${active.length} active · ${archived.length} archived',
      action: CircleButton(
        icon: DialGlyph.plus,
        tooltip: 'Add habit',
        onPressed: () {
          Navigator.of(context).pushNamed('/vices/add');
        },
      ),
      children: <Widget>[
        if (viceListValue.error case final Object error)
          SizedBox(
            height: 320,
            child: ErrorView(
              message: loadErrorMessage('your habits', error),
              onRetry: () =>
                  ref.invalidate(viceListForUserProvider, asReload: true),
            ),
          )
        else if (viceList == null)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (viceList.isEmpty) ...<Widget>[
          const PageFootnote('No habits yet. Tap + to add one.'),
          if (orphans != null) ...<Widget>[
            const SizedBox(height: DialSpace.l),
            _deletedHabitCard(orphans),
          ],
        ] else ...<Widget>[
          const SizedBox(height: DialSpace.l),
          if (active.isNotEmpty) _card(active, marks),
          if (archived.isNotEmpty) ...<Widget>[
            const SectionLabel(ManageData.archivedLabel),
            _card(archived, marks),
          ],
          if (orphans != null) ...<Widget>[
            const SizedBox(height: DialSpace.l),
            _deletedHabitCard(orphans),
          ],
          const PageFootnote(ManageData.colourNote),
        ],
      ],
    );
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    // The counts are not live; the page opened can delete entries.
    if (mounted) {
      ref.invalidate(viceActivityCountForUserProvider);
      ref.invalidate(activityTotalCountForUserProvider);
    }
  }

  // Shown only while the counts say such entries exist.
  Widget _deletedHabitCard(int count) {
    final DialColors colors = DialColors.of(context);
    return DialCard(
      children: <Widget>[
        InkWell(
          onTap: () => _open(DeletedHabitPage.route),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 66),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 4, 8),
              child: Row(
                children: <Widget>[
                  const DeletedHabitPip(size: 14),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          DeletedHabitPage.title,
                          style: DialTypeScale.bodyL.copyWith(
                            height: 1.2,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${DeletedHabitPage.entries(count)} · '
                          '${ManageData.deletedHabitNote}',
                          style: DialTypeScale.bodyS.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: StrokeIcon(
                      DialGlyph.right,
                      size: 18,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(List<Vice> vices, Map<String, HabitMark> marks) => DialCard(
    children: <Widget>[
      for (int i = 0; i < vices.length; i++) ...<Widget>[
        if (i > 0) const CardDivider(indent: 44),
        _row(vices[i], marks[vices[i].id] ?? const HabitMark(0)),
      ],
    ],
  );

  Widget _row(Vice vice, HabitMark mark) {
    final DialColors colors = DialColors.of(context);

    // An archived vice keeps its history, so its row still opens it.
    return InkWell(
      onTap: () => _open('/vices/${vice.id}/activities'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 4, 8),
          child: Row(
            children: <Widget>[
              HabitPip(mark: mark, size: 14),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vice.name,
                      style: DialTypeScale.bodyL.copyWith(
                        height: 1.2,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Consumer(
                      builder: (BuildContext context, WidgetRef ref, _) {
                        final AsyncValue<ActivityCount> count = ref.watch(
                          viceActivityCountProvider(vice.id),
                        );
                        // A re-run keeps the last count until the new one
                        // arrives.
                        final String text = <String>[
                          vice.units.nameFor(2),
                          switch (count.value) {
                            final ActivityCount value => ManageData.countText(
                              value,
                            ),
                            null when count.hasError =>
                              ManageData.countUnavailable,
                            null => '',
                          },
                        ].where((String part) => part.isNotEmpty).join(' · ');
                        return Text(
                          text,
                          style: DialTypeScale.bodyS.copyWith(
                            color: colors.muted,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: StrokeIcon(
                  DialGlyph.right,
                  size: 18,
                  color: colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
