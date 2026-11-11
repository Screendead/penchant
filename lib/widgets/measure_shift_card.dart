import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/widgets/settings_card.dart';

/// One measure's lasting change of level, and the habits that changed with
/// it.
class MeasureShiftCard extends StatelessWidget {
  const MeasureShiftCard({
    super.key,
    required this.shift,
    required this.nameOf,
    required this.locale,
    required this.top,
  });

  final MeasureShift shift;
  final String Function(String habitId) nameOf;
  final String locale;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    return DialCard(
      top: top,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                measureShiftSentence(shift, formatDate(shift.shift.at), locale),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(
                measureShiftBasis(shift, locale),
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
              if (shift.habits.isNotEmpty) const SizedBox(height: DialSpace.s),
              for (final HabitChange change in shift.habits)
                Text(
                  habitChangeLine(change, nameOf(change.habitId), locale),
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
