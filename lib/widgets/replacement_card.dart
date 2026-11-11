import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/replacement_copy.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// A habit's fall and the habits that rose around the same time: the fall as
/// the journal has it, the clearest rise, then the rest as lines.
class ReplacementCardView extends StatelessWidget {
  const ReplacementCardView({
    super.key,
    required this.card,
    required this.nameOf,
    required this.unitOf,
    required this.mark,
    required this.locale,
    required this.top,
  });

  final ReplacementCard card;
  final String Function(String id) nameOf;
  final Unit Function(String id) unitOf;
  final HabitMark mark;
  final String locale;
  final double top;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final String habit = nameOf(card.habitId);
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
                fallSentence(
                  card.fall,
                  habit,
                  locale,
                  unit: unitOf(card.habitId),
                ),
                style: small,
              ),
              ReplacementRisers(card: card, nameOf: nameOf, unitOf: unitOf, locale: locale),
            ],
          ),
        ),
      ],
    );
  }
}

/// The habits that rose as [card]'s habit fell, under a card that has already
/// stated the fall: the clearest rise, the rest as lines, then what it cannot
/// say.
class ReplacementRisers extends StatelessWidget {
  const ReplacementRisers({
    super.key,
    required this.card,
    required this.nameOf,
    required this.unitOf,
    required this.locale,
  });

  final ReplacementCard card;
  final String Function(String id) nameOf;
  final Unit Function(String id) unitOf;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final Replacement headline = card.risers.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: DialSpace.xs),
        Text(
          replacementSentence(
            headline,
            nameOf(headline.riserId),
            locale,
            unit: unitOf(headline.riserId),
          ),
          style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: DialSpace.xs),
        Text(replacementRange(headline, locale), style: small),
        Text(replacementBasis(headline), style: small),
        if (card.risers.length > 1) const SizedBox(height: DialSpace.s),
        for (final Replacement other in card.risers.skip(1))
          Text(
            replacementLine(
              other,
              nameOf(other.riserId),
              locale,
              unit: unitOf(other.riserId),
            ),
            style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
          ),
        const SizedBox(height: DialSpace.s),
        Text(replacementCaveat, style: small),
      ],
    );
  }
}
