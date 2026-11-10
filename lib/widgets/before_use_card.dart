import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/before_use_copy.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// What comes before one habit: its largest finding, then the rest as lines.
class BeforeUseCardView extends StatelessWidget {
  const BeforeUseCardView({
    super.key,
    required this.card,
    required this.habit,
    required this.unit,
    required this.mark,
    required this.locale,
    required this.top,
  });

  final BeforeUseCard card;
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
                beforeUseSentence(card.headline, habit, locale, unit: unit),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(findingRange(card.headline.asFinding, locale), style: small),
              Text(beforeUseBasis(card.headline, habit), style: small),
              if (card.others.isNotEmpty) const SizedBox(height: DialSpace.s),
              for (final BeforeUse other in card.others)
                Text(
                  beforeUseLine(other, locale, unit: unit),
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
