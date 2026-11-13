import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/widgets/time_dial.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

// The amount sheet's fields: a stepper over a typed amount, the entry's time
// on the mini dial, its triggers, and the optional urge and note. A new entry's sheet and the entry editor
// both build them, inside their own Form.
class AmountFields extends ConsumerWidget {
  const AmountFields({
    super.key,
    required this.quantityController,
    required this.unit,
    required this.timeController,
    this.editing,
    required this.triggers,
    required this.onTriggersChanged,
    required this.viceID,
    required this.viceName,
    required this.urge,
    required this.onUrgeChanged,
    required this.noteController,
    this.answersEnabled = true,
    this.enabled = true,
    this.quantityValidator = quantityError,
    this.error,
  });

  static const String quantityLabel = 'Quantity';
  static const String lessTooltip = 'Less';
  static const String moreTooltip = 'More';
  // A habit typically logged in tens steps by fives, from its stored typical
  // entry.
  static int stepFor(double? typical) =>
      typical != null && typical >= 10 ? 5 : 1;

  final TextEditingController quantityController;
  final UnitWords unit;
  final EntryTimeController timeController;
  // The id of the entry being edited, which the dial leaves off its faded
  // entries.
  final String? editing;
  final List<String> triggers;
  final ValueChanged<List<String>> onTriggersChanged;
  final String? viceID;
  final String viceName;
  final int? urge;
  final ValueChanged<int?> onUrgeChanged;
  final TextEditingController noteController;
  // False for a locked entry, whose urge and note are not known.
  final bool answersEnabled;
  final bool enabled;
  final FormFieldValidator<String> quantityValidator;
  final String? error;

  num get _typed => parseAmount(quantityController.text) ?? 0;

  // A step of one keeps a typed fraction; a larger one lands on its multiples.
  void _stepBy(int step, int direction) {
    final num typed = _typed;
    final num next = step == 1
        ? typed + direction
        : direction > 0
        ? ((typed / step).floor() + 1) * step
        : ((typed / step).ceil() - 1) * step;
    quantityController.text = formatAmount(next < 1 ? 1 : next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int step = stepFor(ref.watch(storedTypicalsProvider)[viceID]);
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: quantityController,
          builder: (BuildContext context, _) => Row(
            children: [
              StepButton(
                glyph: DialGlyph.minus,
                tooltip: lessTooltip,
                onPressed: enabled && _typed > 1
                    ? () => _stepBy(step, -1)
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: quantityController,
                      enabled: enabled,
                      textAlign: TextAlign.center,
                      style: DialTypeScale.monoXL.copyWith(
                        fontSize: 42,
                        color: scheme.onSurface,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: quantityLabel,
                        floatingLabelAlignment: FloatingLabelAlignment.center,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      validator: quantityValidator,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unit.nameFor(_typed),
                      style: DialTypeScale.bodyS.copyWith(
                        color: colors.muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              StepButton(
                glyph: DialGlyph.plus,
                tooltip: moreTooltip,
                onPressed: enabled ? () => _stepBy(step, 1) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        EntryTimeField(
          controller: timeController,
          editing: editing,
          enabled: enabled,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TriggersField(
            value: triggers,
            onChanged: onTriggersChanged,
            viceID: viceID,
            viceName: viceName,
            at: () => timeController.value,
            enabled: enabled,
          ),
        ),
        const SizedBox(height: DialSpace.s),
        UrgeField(
          value: urge,
          onChanged: onUrgeChanged,
          enabled: enabled && answersEnabled,
        ),
        const SizedBox(height: DialSpace.m),
        NoteField(
          controller: noteController,
          enabled: enabled && answersEnabled,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: scheme.error)),
        ],
      ],
    );
  }
}

// The stepper's 56 pt round buttons; Edit Habit's line takes them too.
class StepButton extends StatelessWidget {
  const StepButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
  });

  static const double size = 56;

  final DialGlyph glyph;
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
        icon: StrokeIcon(glyph, size: 22),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(size),
          minimumSize: const Size.square(size),
          backgroundColor: colors.surface2,
          disabledBackgroundColor: colors.surface2,
          foregroundColor: scheme.onSurface,
          disabledForegroundColor: scheme.onSurface,
        ),
      ),
    );
  }
}
