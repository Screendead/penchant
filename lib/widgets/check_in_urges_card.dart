import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/check_in_urges.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The urge noted at a habit's entries against the urge at random check-ins.
class CheckInUrgesCard extends StatelessWidget {
  const CheckInUrgesCard({
    super.key,
    required this.urge,
    required this.habit,
    required this.mark,
    required this.locale,
    required this.top,
  });

  final CheckInUrge urge;
  final String habit;
  final HabitMark mark;
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
              Row(
                children: <Widget>[
                  HabitPip(mark: mark),
                  const SizedBox(width: DialSpace.xs),
                  Expanded(
                    child: Text(
                      habit,
                      style: DialTypeScale.label.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                checkInUrgeSentence(urge, habit, locale),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(
                checkInUrgeBasis(urge),
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
