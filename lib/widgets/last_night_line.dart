import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/last_night_provider.dart';

/// Today's morning line under the dial: last night's sleeping heart rate
/// against the person's usual. Opens Insights, where the full check leads.
/// Nothing until Health answers, after noon, or without a value for last
/// night, so it never holds Today up.
class LastNightLine extends ConsumerWidget {
  const LastNightLine({super.key});

  static const String lead = 'Last night';

  /// "heart rate 3 bpm above usual"; one line at 390 pt after "Last night".
  static String body(NightCompare heart) => switch (heart.side) {
    NightSide.above => 'heart rate ${heart.shownBy} bpm above usual',
    NightSide.below => 'heart rate ${heart.shownBy} bpm below usual',
    NightSide.usual => 'heart rate within usual',
  };

  /// The full meaning for a screen reader.
  static String spoken(NightCompare heart) => switch (heart.side) {
    NightSide.above =>
      'sleeping heart rate ${heart.shownBy} bpm above your usual',
    NightSide.below =>
      'sleeping heart rate ${heart.shownBy} bpm below your usual',
    NightSide.usual => 'sleeping heart rate within your usual range',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(morningProvider)) return const SizedBox.shrink();
    final NightCompare? heart = ref
        .watch(lastNightProvider)
        .value
        ?.sleepingHeartRate;
    if (heart == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final BorderRadius radius = BorderRadius.circular(DialRadius.tile);
    final TextStyle text = DialTypeScale.bodyS.copyWith(
      fontSize: 14,
      height: 1.4,
      color: scheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.only(top: DialSpace.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: radius,
          border: Border.all(color: colors.line),
          boxShadow: DialShadows.card(theme.brightness),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: () => Navigator.of(context).pushNamed(InsightsPage.route),
            child: Semantics(
              button: true,
              label: '$lead, ${spoken(heart)}',
              hint: 'Opens Insights',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: lead,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: ' · ${body(heart)}'),
                            ],
                          ),
                          style: text,
                        ),
                      ),
                      const SizedBox(width: DialSpace.xs),
                      StrokeIcon(
                        DialGlyph.right,
                        size: 18,
                        color: scheme.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
