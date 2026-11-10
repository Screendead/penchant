import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// A pill that is one of a set: a habit chip, or a segment of [PillSegments].
// It is announced as selected or not, and focus draws the accent edge.
class PillToggle extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.selected,
    required this.onPressed,
    required this.child,
    required this.color,
    required this.selectedColor,
    required this.selectedSide,
    this.restForeground,
    this.semanticsLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: DialSpace.s),
    this.minHeight = DialSize.chipHeight,
    this.exclusive = true,
  });

  final bool selected;
  // Null disables it.
  final VoidCallback? onPressed;
  final Widget child;
  final Color color;
  final Color selectedColor;
  final BorderSide selectedSide;
  // The label's colour when not selected; muted if null.
  final Color? restForeground;
  final String? semanticsLabel;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  // False when several of its group can be on at once.
  final bool exclusive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);

    return MergeSemantics(
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: exclusive,
        label: semanticsLabel,
        child: TextButton(
          onPressed: onPressed,
          style:
              TextButton.styleFrom(
                backgroundColor: selected ? selectedColor : color,
                foregroundColor: selected
                    ? scheme.onSurface
                    : restForeground ?? colors.muted,
                minimumSize: Size(DialSize.minTapTarget, minHeight),
                padding: padding,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
                textStyle: Theme.of(context).textTheme.labelMedium,
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (Set<WidgetState> s) => s.contains(WidgetState.focused)
                      ? BorderSide(color: scheme.primary, width: 2)
                      : selected
                      ? selectedSide
                      : BorderSide.none,
                ),
              ),
          child: semanticsLabel == null
              ? child
              : ExcludeSemantics(child: child),
        ),
      ),
    );
  }
}

// A small segmented control: a recessed track holding a raised thumb on the
// selected segment.
class PillSegments<T> extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  // Each value, its shown label, and what a screen reader says for it.
  final List<({T value, String label, String spoken})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  // Tall enough with the track's padding for a 44 pt target.
  static const double _segmentHeight = DialSize.minTapTarget - 6;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);

    // At large text sizes the track is wider than the screen; it scrolls.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.surface2,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final ({T value, String label, String spoken}) s in segments)
                PillToggle(
                  selected: s.value == selected,
                  onPressed: () => onChanged(s.value),
                  color: Colors.transparent,
                  selectedColor: scheme.surfaceContainerLow,
                  selectedSide: BorderSide(color: scheme.outline),
                  semanticsLabel: s.spoken,
                  minHeight: _segmentHeight,
                  child: Text(s.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
