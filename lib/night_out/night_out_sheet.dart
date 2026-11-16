import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/night_out/night_out.dart';
import 'package:tracker/widgets/amount_sheet_frame.dart';
import 'package:tracker/widgets/bead_painter.dart';

const String startNightLabel = 'Start a night';

/// "Start a night" on [vice]: what the Lock Screen will show, and whether it
/// names the habit.
Future<void> showStartNightSheet(
  BuildContext context, {
  required Vice vice,
  required HabitMark mark,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => StartNightSheet(vice: vice, mark: mark),
);

class StartNightSheet extends ConsumerStatefulWidget {
  const StartNightSheet({
    super.key,
    required this.vice,
    required this.mark,
    this.now,
  });

  final Vice vice;
  final HabitMark mark;
  // The preview's start time; the clock's when null.
  final DateTime? now;

  @override
  ConsumerState<StartNightSheet> createState() => _StartNightSheetState();
}

class _StartNightSheetState extends ConsumerState<StartNightSheet> {
  bool _showHabit = false;
  bool _starting = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await ref
          .read(nightOutProvider.notifier)
          .start(
            viceID: widget.vice.id,
            habit: _showHabit ? widget.vice.name : null,
            slot: _showHabit ? widget.mark.slot : null,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on NightStartRefused catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final String name = widget.vice.name;
    final String since = formatTime(
      widget.now ?? DateTime.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return AmountSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Start a night on $name', style: theme.textTheme.titleLarge),
          const SizedBox(height: DialSpace.xs),
          Text(
            'Your Lock Screen counts $name from now, with a +1 that logs one '
            'without unlocking. It ends by itself at 06:00 or after 8 hours, '
            'whichever comes first, or when you end it on Today.',
            style: DialTypeScale.body.copyWith(color: colors.muted),
          ),
          const SizedBox(height: DialSpace.m),
          NightLockPreview(
            label: _showHabit ? name : 'Tonight',
            mark: _showHabit ? widget.mark : null,
            since: since,
          ),
          const SizedBox(height: DialSpace.xs),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _showHabit,
            onChanged: _starting
                ? null
                : (bool on) => setState(() => _showHabit = on),
            title: Text('Show $name’s name and colour'),
            subtitle: Text(
              'Anyone who sees your Lock Screen will see it. Off, it says '
              '“Tonight”.',
              style: DialTypeScale.bodyS.copyWith(color: colors.muted),
            ),
          ),
          if (_error case final String error) ...<Widget>[
            const SizedBox(height: DialSpace.xs),
            Text(
              error,
              style: DialTypeScale.bodyS.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: DialSpace.m),
          FilledButton(
            onPressed: _starting ? null : _start,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

/// The Lock Screen's line as the person will see it, drawn in the app.
class NightLockPreview extends StatelessWidget {
  const NightLockPreview({
    super.key,
    required this.label,
    required this.mark,
    required this.since,
  });

  final String label;
  // Null draws the neutral ink ring.
  final HabitMark? mark;
  final String since;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final HabitMark? shown = mark;
    return Semantics(
      label: 'Lock Screen preview: $label, 0, since $since',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(DialRadius.tile + 6),
        ),
        child: Row(
          children: <Widget>[
            if (shown == null)
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.onSurface, width: 2),
                ),
              )
            else
              HabitPip(mark: shown, size: 12),
            const SizedBox(width: DialSpace.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.displayM.copyWith(
                      color: scheme.onSurface,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'since $since',
                    style: DialTypeScale.bodyS.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            Text(
              '0',
              style: type.monoL.copyWith(
                color: shown == null
                    ? scheme.onSurface
                    : colors.habitInk(shown),
              ),
            ),
            const SizedBox(width: DialSpace.s),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surface2,
                border: Border.all(color: colors.line),
              ),
              child: Text(
                '+1',
                style: type.monoM.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's line while a night runs: the habit, its count since the start,
/// when it ends, and End.
class NightStrip extends ConsumerWidget {
  const NightStrip({
    super.key,
    required this.night,
    required this.vice,
    required this.mark,
  });

  final Night night;
  final Vice vice;
  final HabitMark mark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final String since = formatTime(night.start, alwaysUse24HourFormat: h24);
    final String ends = formatTime(night.endBy, alwaysUse24HourFormat: h24);
    final String title = 'Night out: ${vice.name}';
    final String line =
        '${vice.units.label(night.count)} since $since · ends $ends';
    return Padding(
      padding: const EdgeInsets.only(bottom: DialSpace.xs),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            HabitPip(mark: mark, size: 10),
            const SizedBox(width: DialSpace.xs),
            Expanded(
              child: Semantics(
                label: '$title. $line. On your Lock Screen.',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DialTypeScale.body.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 20 / 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        style: DialTypeScale.bodyS.copyWith(
                          color: colors.muted,
                        ),
                        children: <InlineSpan>[
                          TextSpan(
                            text: formatCount(night.count),
                            style: type.monoM.copyWith(
                              fontSize: 13,
                              color: colors.habitInk(mark),
                            ),
                          ),
                          TextSpan(
                            text:
                                ' ${vice.units.nameFor(night.count)} since '
                                '$since · ends $ends',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(nightOutProvider.notifier).end(),
              style: TextButton.styleFrom(
                minimumSize: const Size(DialSize.minTapTarget, 44),
                foregroundColor: scheme.onSurface,
              ),
              child: Text(
                'End',
                semanticsLabel: 'End the night out',
                style: DialTypeScale.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
