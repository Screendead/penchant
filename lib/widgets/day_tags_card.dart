import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/day_tags.dart';
import 'package:tracker/insights/day_tags_copy.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The day tags a habit's day totals go with: the largest difference in a
/// sentence, the entry finding for the same tag beside it when they agree,
/// then the rest as lines.
class DayTagsCard extends StatelessWidget {
  const DayTagsCard({
    super.key,
    required this.card,
    required this.habit,
    required this.unit,
    required this.mark,
    required this.locale,
    required this.top,
  });

  final DayTagCard card;
  final String habit;
  final Unit unit;
  final HabitMark mark;
  final String locale;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final TextStyle body = DialTypeScale.bodyL.copyWith(
      color: scheme.onSurface,
    );
    final TriggerAmount? byEntry = card.headlineByEntry;
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
                  if (byEntry != null) Text(dayTagJoined, style: small),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                dayTagSentence(card.headline, habit, locale, unit: unit),
                style: body,
              ),
              const SizedBox(height: DialSpace.xs),
              Text(dayTagBasis(card.habit, card.headline), style: small),
              if (byEntry != null) ...<Widget>[
                const SizedBox(height: DialSpace.s),
                Text(triggerSentence(byEntry, habit), style: body),
              ],
              if (card.found.length > 1) const SizedBox(height: DialSpace.s),
              for (final DayTagAmount other in card.found.skip(1))
                Text(
                  dayTagLine(
                    other,
                    locale,
                    byEntry: card.byEntry.containsKey(other.tag),
                  ),
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
