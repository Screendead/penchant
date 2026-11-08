import 'package:flutter/material.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/design/dial_theme.dart';

/// The design system's segmented control: one thumb sliding between the
/// choices, each at least a tap target tall.
class DialSegments<T> extends StatelessWidget {
  const DialSegments({
    super.key,
    required this.choices,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> choices;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final Duration slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final int index = choices.indexOf(selected);
    final int count = choices.length;
    return Container(
      padding: const EdgeInsets.all(DialSpace.xxs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DialRadius.pill),
        border: Border.all(color: colors.line),
        boxShadow: DialShadows.card(brightness),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AnimatedAlign(
              duration: slide,
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + 2 * index / (count - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(DialRadius.pill),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              for (final T choice in choices)
                Expanded(
                  child: _Segment(
                    label: label(choice),
                    selected: choice == selected,
                    onTap: () => onChanged(choice),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool ring =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Semantics(
      button: true,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (bool focused) => setState(() => _focused = focused),
        customBorder: const StadiumBorder(),
        child: Container(
          constraints: const BoxConstraints(minHeight: DialSize.minTapTarget),
          alignment: Alignment.center,
          decoration: ring
              ? ShapeDecoration(
                  shape: StadiumBorder(
                    side: BorderSide(
                      // The selected thumb is accent, which primary matches.
                      color: widget.selected
                          ? scheme.onPrimary
                          : scheme.primary,
                      width: 2,
                    ),
                  ),
                )
              : null,
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: DialFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1,
              color: widget.selected ? scheme.onPrimary : colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
