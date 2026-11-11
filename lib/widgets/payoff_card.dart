import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/replacement_card.dart';
import 'package:tracker/widgets/settings_card.dart';

/// A habit's fall and what moved since: the fall as the journal has it, the
/// largest finding, then the rest as lines; with no finding, why not. The
/// habits that rose around the same time, [replacement], follow under the
/// same fall. A card with neither is a row, not this.
class PayoffCardView extends StatelessWidget {
  const PayoffCardView({
    super.key,
    required this.card,
    required this.habit,
    required this.unit,
    required this.mark,
    required this.locale,
    required this.top,
    this.replacement,
    this.nameOf,
    this.unitOf,
  }) : assert(replacement == null || (nameOf != null && unitOf != null));

  final PayoffCard card;
  final String habit;
  final Unit unit;
  final HabitMark mark;
  final String locale;
  final double top;

  /// With [nameOf] and [unitOf], which name and measure its risers.
  final ReplacementCard? replacement;
  final String Function(String id)? nameOf;
  final Unit Function(String id)? unitOf;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final Payoff? headline = card.findings.firstOrNull;
    final ReplacementCard? replacement = this.replacement;
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
                fallSentence(card.fall, habit, locale, unit: unit),
                style: small,
              ),
              if (headline != null) ...<Widget>[
                const SizedBox(height: DialSpace.xs),
                Text(
                  payoffSentence(headline, locale),
                  style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: DialSpace.xs),
                Text(findingRange(headline.asFinding, locale), style: small),
                Text(payoffBasis(headline), style: small),
                if (card.findings.length > 1)
                  const SizedBox(height: DialSpace.s),
                for (final Payoff other in card.findings.skip(1))
                  Text(
                    payoffLine(other, locale),
                    style: DialTypeScale.bodyS.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
              ] else if (card.refusal case final Payoff refused)
                Text(payoffRefusal(refused), style: small),
              if (replacement != null) ...<Widget>[
                if (headline != null) const SizedBox(height: DialSpace.s),
                ReplacementRisers(
                  card: replacement,
                  nameOf: nameOf!,
                  unitOf: unitOf!,
                  locale: locale,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
