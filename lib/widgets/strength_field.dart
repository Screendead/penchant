import 'package:flutter/material.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/tap_away.dart';

// An entry's own strength in the amount sheet and the editor, for a habit
// with a strength: blank keeps the habit's. Under it, what this entry comes to
// in the habit's unit.
class StrengthField extends StatelessWidget {
  const StrengthField({
    super.key,
    required this.strength,
    required this.controller,
    required this.quantityController,
    this.enabled = true,
  });

  static const Key fieldKey = ValueKey<String>('entry-strength');

  static String label(HabitStrength strength) =>
      strength.unit.alcohol ? 'Strength this time' : 'Caffeine this time';

  final HabitStrength strength;
  final TextEditingController controller;
  final TextEditingController quantityController;
  final bool enabled;

  // The typed override, or null for blank or not a number.
  static double? typed(String text) => switch (parseAmount(text)) {
    final num value when value > 0 => roundStrength(value),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final bool alcohol = strength.unit.alcohol;
    final double? usual = alcohol ? strength.abv : strength.caffeineMg;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        controller,
        quantityController,
      ]),
      builder: (BuildContext context, _) {
        final double? own = typed(controller.text);
        final double? each = alcohol
            ? strength.perServing(abv: own)
            : strength.perServing(caffeineMg: own);
        final num quantity = parseAmount(quantityController.text) ?? 0;
        final String usualWords = usual == null
            ? 'Not set for this habit'
            : 'Blank uses the usual ${formatCount(usual)}'
                  '${alcohol ? '%' : ' mg'}';
        return TextFormField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          onTapOutside: closeKeyboardOnTapOutside,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label(strength),
            hintText: usual == null ? null : formatAmount(usual),
            suffixText: alcohol ? '% ABV' : 'mg each',
            helperText: each == null
                ? usualWords
                : '$usualWords · this entry '
                      '${strength.label(each * quantity)}',
            helperMaxLines: 2,
          ),
          validator: (String? value) =>
              strengthError(value, alcohol ? maxAbv : maxCaffeineMg),
        );
      },
    );
  }
}
