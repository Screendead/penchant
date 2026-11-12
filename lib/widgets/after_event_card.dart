import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/after_event_copy.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

/// One habit's finding of how often it follows a calendar event.
class AfterEventCardView extends StatelessWidget {
  const AfterEventCardView({
    super.key,
    required this.finding,
    required this.habit,
    required this.mark,
    required this.locale,
    required this.top,
  });

  final AfterEvent finding;
  final String habit;
  final HabitMark mark;
  final String locale;
  final double top;

  @override
  Widget build(BuildContext context) => SourceFindingCard(
    habit: habit,
    mark: mark,
    sentence: afterEventSentence(finding, habit, locale),
    details: <String>[
      afterEventRange(finding, locale),
      afterEventBasis(finding),
    ],
    top: top,
  );
}

/// One habit's finding against a source read on the device: the habit, a
/// sentence, then smaller lines.
class SourceFindingCard extends StatelessWidget {
  const SourceFindingCard({
    super.key,
    required this.habit,
    required this.mark,
    required this.sentence,
    required this.details,
    required this.top,
  });

  final String habit;
  final HabitMark mark;
  final String sentence;
  final List<String> details;
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
                sentence,
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.xs),
              for (final String line in details) Text(line, style: small),
            ],
          ),
        ),
      ],
    );
  }
}
