import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/notes/follow_up.dart';

/// A saved follow-up question and its answer, read-only, under the note it
/// was asked about.
class SavedFollowUp extends StatelessWidget {
  const SavedFollowUp({super.key, required this.followUp});

  final FollowUp followUp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(DialRadius.tile),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DialSpace.s,
          vertical: DialSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              askedLine(followUp.question, followUp.quote),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: DialSpace.xs),
            Text(followUp.answer, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
