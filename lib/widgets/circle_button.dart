import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// The 40 pt round button for day arrows, close and back.
class CircleButton extends StatelessWidget {
  const CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);

    return Opacity(
      opacity: onPressed == null ? 0.35 : 1,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(DialSize.circleButton),
          minimumSize: const Size.square(DialSize.circleButton),
          tapTargetSize: MaterialTapTargetSize.padded,
          backgroundColor: scheme.surfaceContainerLow,
          disabledBackgroundColor: scheme.surfaceContainerLow,
          foregroundColor: scheme.onSurface,
          disabledForegroundColor: scheme.onSurface,
          side: BorderSide(color: colors.line),
        ),
      ),
    );
  }
}
