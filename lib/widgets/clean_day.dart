import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';

class CleanDay extends StatelessWidget {
  const CleanDay({super.key, required this.isToday, this.offline = false});

  final bool isToday;
  // Offline, an empty day may only be one this device never fetched.
  final bool offline;

  static const String offlineHeadline = 'Nothing on this device';
  static const String offlineBody =
      'Entries made elsewhere show once you are back online.';

  static String headline({required bool isToday}) =>
      isToday ? 'A clear day so far' : 'A clear day';

  static String body({required bool isToday}) =>
      isToday ? 'Nothing recorded today.' : 'Nothing recorded on this day.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors dial = DialColors.of(context);

    // Scrolls when large text and the keyboard leave too little height.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dial.clear,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco_outlined, color: dial.clearInk),
                const SizedBox(height: 8),
                Text(
                  offline ? offlineHeadline : headline(isToday: isToday),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: dial.clearInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offline ? offlineBody : body(isToday: isToday),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: dial.clearInk,
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
