import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The triggers a habit's tagged entries hold more or less with: the largest
/// difference in a sentence, then the rest as lines.
class TriggerAmountsCard extends StatelessWidget {
  const TriggerAmountsCard({
    super.key,
    required this.card,
    required this.habit,
    required this.mark,
    required this.top,
  });

  final TriggerCard card;
  final String habit;
  final HabitMark mark;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
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
                triggerSentence(card.headline, habit),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(triggerBasis(card.habit, card.headline), style: small),
              if (card.found.length > 1) const SizedBox(height: DialSpace.s),
              for (final TriggerAmount other in card.found.skip(1))
                Text(
                  triggerLine(other),
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
