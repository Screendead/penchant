import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The habits one habit tends to come within minutes of: the strongest in a
/// sentence, then the rest as lines.
class HabitFollowsCard extends StatelessWidget {
  const HabitFollowsCard({
    super.key,
    required this.card,
    required this.nameOf,
    required this.mark,
    required this.top,
  });

  final FollowsCard card;
  final String Function(String habitId) nameOf;
  final HabitMark mark;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final HabitFollows headline = card.headline;
    final String habit = nameOf(card.habitId);
    final String lead = nameOf(headline.leadId);
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
                followsSentence(headline, lead, habit),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(followsBasis(headline, lead), style: small),
              if (card.others.isNotEmpty) const SizedBox(height: DialSpace.s),
              for (final HabitFollows other in card.others)
                Text(
                  followsLine(other, nameOf(other.leadId)),
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
