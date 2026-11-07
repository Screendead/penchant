import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/appearance_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Settings › Appearance: the design system's segmented control on a ground.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  static const String route = '/settings/appearance';
  static const List<ThemeMode> choices = <ThemeMode>[
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(appearanceProvider);
    return CardPage(
      title: 'Appearance',
      children: <Widget>[
        const SizedBox(height: DialSpace.l),
        _Segments(
          selected: mode,
          onChanged: ref.read(appearanceProvider.notifier).choose,
        ),
        const CardFoot(
          'Match system follows your phone’s light or dark setting. '
          'Saved on this device only.',
        ),
      ],
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final Duration slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final int index = AppearanceSettings.choices.indexOf(selected);
    final int count = AppearanceSettings.choices.length;
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
              for (final ThemeMode mode in AppearanceSettings.choices)
                Expanded(
                  child: _Segment(
                    label: appearanceLabel(mode),
                    selected: mode == selected,
                    onTap: () => onChanged(mode),
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
                    color: widget.selected ? scheme.onPrimary : scheme.primary,
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
