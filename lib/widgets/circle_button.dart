import 'package:flutter/material.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// The 40 pt round button for day arrows, close and back, with a 44 pt target
// and the card shadow in light.
class CircleButton extends StatelessWidget {
  const CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.focusNode,
  });

  final DialGlyph icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  // Material pads a target to 48 at standard density; one step denser pads it
  // to 44, the iOS minimum, which is the row height the mock-up measures.
  static const VisualDensity _density = VisualDensity(
    horizontal: -1,
    vertical: -1,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);

    return Opacity(
      opacity: onPressed == null ? 0.35 : 1,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: DialShadows.card(theme.brightness),
            ),
            child: const SizedBox.square(dimension: DialSize.circleButton),
          ),
          IconButton(
            tooltip: tooltip,
            focusNode: focusNode,
            onPressed: onPressed,
            icon: StrokeIcon(icon, size: 20),
            style:
                IconButton.styleFrom(
                  fixedSize: const Size.square(DialSize.circleButton),
                  minimumSize: const Size.square(DialSize.circleButton),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: _density,
                  backgroundColor: scheme.surfaceContainerLow,
                  disabledBackgroundColor: scheme.surfaceContainerLow,
                  foregroundColor: scheme.onSurface,
                  disabledForegroundColor: scheme.onSurface,
                ).copyWith(
                  // A side set here replaces the theme's focus ring, so it is
                  // drawn here too.
                  side: WidgetStateProperty.resolveWith(
                    (Set<WidgetState> s) => s.contains(WidgetState.focused)
                        ? BorderSide(color: scheme.primary, width: 2)
                        : BorderSide(color: colors.line),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
