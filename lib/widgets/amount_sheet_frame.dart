import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/circle_button.dart';

// The amount sheet's padding, its grab bar, and room for the keyboard. The
// new-entry sheet and the entry editor both sit in one.
class AmountSheetFrame extends StatelessWidget {
  const AmountSheetFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    // Its own Material, so it also renders outside a sheet's.
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          // Clear of the home indicator, as the mock-up's sheet is, or of
          // the keyboard while it is up (the padding drops to 0 then).
          math.max(
            MediaQuery.viewInsetsOf(context).bottom + 22,
            math.max(MediaQuery.paddingOf(context).bottom, 22),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

// The sheet's title row for a known habit: its mark, its name and Close.
class SheetHabitHeader extends ConsumerWidget {
  const SheetHabitHeader({super.key, required this.vice, required this.onClose});

  final Vice vice;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vice> all = ref.watch(viceListProvider).value ?? <Vice>[vice];
    final HabitMark? mark = habitMarks(all)[vice.id];
    return Row(
      children: [
        if (mark != null) ...[
          HabitPip(mark: mark, size: 12),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            vice.name,
            style: DialTypeScale.displayM.copyWith(fontSize: 20),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SheetCloseButton(onPressed: onClose),
      ],
    );
  }
}

class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => CircleButton(
    flat: true,
    icon: DialGlyph.close,
    tooltip: 'Close',
    onPressed: onPressed,
  );
}
