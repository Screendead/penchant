import 'package:flutter/material.dart';

class CleanDay extends StatelessWidget {
  const CleanDay({super.key, required this.isToday});

  final bool isToday;

  static String headline({required bool isToday}) =>
      isToday ? 'A clear day so far' : 'A clear day';

  static String body({required bool isToday}) =>
      isToday ? 'Nothing recorded today.' : 'Nothing recorded on this day.';

  // A green tonal scheme in the ambient brightness: Material 3 pairs each
  // container role with an on-container role at 4.5:1 or better.
  static ColorScheme colors(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: Colors.green, brightness: brightness);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme green = colors(theme.brightness);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: green.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco_outlined, color: green.onPrimaryContainer),
                const SizedBox(height: 8),
                Text(
                  headline(isToday: isToday),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: green.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body(isToday: isToday),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: green.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
