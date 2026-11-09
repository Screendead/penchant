import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

/// A section with nothing to say yet: an outlined box, not a card, so it
/// never reads as a finding. [progress], 0 to 1, draws a meter under it.
class NotYetBox extends StatelessWidget {
  const NotYetBox(this.title, {super.key, required this.body, this.progress});

  final String title;
  final String body;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final double? progress = this.progress;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DialRadius.card),
        border: Border.all(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: DialSpace.xxs),
            Text(
              body,
              style: DialTypeScale.bodyS.copyWith(color: colors.muted),
            ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.only(top: DialSpace.xs),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DialRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    color: scheme.primary,
                    backgroundColor: colors.surface2,
                    semanticsLabel: title,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
