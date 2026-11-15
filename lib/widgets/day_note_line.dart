import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/notes/day_note_route.dart';
import 'package:tracker/providers/day_note_provider.dart';

/// The shown day's note under the tallies, its first line, opening the note.
/// Nothing while there is none or it is loading.
class DayNoteLine extends ConsumerWidget {
  const DayNoteLine({super.key, required this.day});

  final DateTime day;

  static const String lead = 'Note';
  static const String lockedBody = 'cannot be opened here';

  static String firstLine(DayNote note) =>
      note.locked ? lockedBody : note.text.trim().split('\n').first.trim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DayNote? note = ref.watch(dayNoteProvider(day)).value;
    if (note == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final BorderRadius radius = BorderRadius.circular(DialRadius.tile);
    final String body = firstLine(note);
    return Padding(
      padding: const EdgeInsets.only(top: DialSpace.s),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: radius,
          border: Border.all(color: colors.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: () => Navigator.of(context).pushNamed(dayNoteRoute(day)),
            child: Semantics(
              button: true,
              label: '$lead, $body',
              hint: 'Opens the note about this day',
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
                              const TextSpan(
                                text: lead,
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: ' · $body'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DialTypeScale.bodyS.copyWith(
                            fontSize: 14,
                            height: 1.4,
                            color: colors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: DialSpace.xs),
                      StrokeIcon(
                        DialGlyph.right,
                        size: 18,
                        color: colors.muted,
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
