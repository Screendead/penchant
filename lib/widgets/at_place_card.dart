import 'package:flutter/material.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_copy.dart';
import 'package:tracker/widgets/after_event_card.dart';

/// One habit's finding of how often it is logged at one of the person's
/// places.
class AtPlaceCardView extends StatelessWidget {
  const AtPlaceCardView({
    super.key,
    required this.finding,
    required this.habit,
    required this.place,
    required this.mark,
    required this.locale,
    required this.top,
  });

  final AtPlace finding;
  final String habit;
  final String place;
  final HabitMark mark;
  final String locale;
  final double top;

  @override
  Widget build(BuildContext context) => SourceFindingCard(
    habit: habit,
    mark: mark,
    sentence: atPlaceSentence(finding, habit, place, locale),
    details: <String>[atPlaceRange(finding, locale), atPlaceBasis(finding)],
    top: top,
  );
}
