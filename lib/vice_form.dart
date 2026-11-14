import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/amount_fields.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/pill_toggle.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';
import 'package:tracker/widgets/tap_away.dart';

// Adds a vice, or with [vice] edits that one.
class ViceForm extends ConsumerStatefulWidget {
  const ViceForm({super.key, this.vice});

  static const String lockedMessage =
      'Not saved. This habit did not open with your journal key, so its '
      'name and unit cannot be changed here.';

  static const Key unitLabelKey = ValueKey<String>('vice-form-unit-label');
  static const Key unitSingularKey = ValueKey<String>(
    'vice-form-unit-singular',
  );
  static const Key costKey = ValueKey<String>('vice-form-cost');
  static const Key currencyKey = ValueKey<String>('vice-form-currency');
  static const Key lineAmountKey = ValueKey<String>('vice-form-line-amount');

  static const String lineLabel = 'Your line (optional)';
  static const String lineNone = 'None';
  static const String lineHelp =
      'Shown as a mark on Today and a dashed line in Trends. Nothing else '
      'changes: no alerts, no streaks, no colour for going over.';

  final Vice? vice;

  @override
  ConsumerState<ViceForm> createState() => _ViceFormState();
}

class _ViceFormState extends ConsumerState<ViceForm> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  // EditVice rebuilds this with the live document, so a change is measured
  // against what the form opened with, not against [widget.vice].
  late final Vice? opened = widget.vice;
  late final TextEditingController viceNameController = TextEditingController(
    text: opened?.name,
  );
  late Unit? unit = opened?.unit;
  // A vice written before categories opens on the guess the migration makes.
  late ViceCategory category = switch (opened) {
    null => ViceCategory.fallback,
    final Vice vice when !vice.categoryStored => guessCategory(vice.name),
    final Vice vice => vice.category,
  };
  late final TextEditingController unitLabelController = TextEditingController(
    text: opened?.unitLabel,
  );
  late final TextEditingController unitSingularController =
      TextEditingController(text: opened?.unitSingular);
  // Shown to three places, so an untouched field keeps the stored cost
  // rather than its rounding.
  late final String openedCostText = switch (opened?.costPerUnit) {
    final double cost => formatAmount(cost),
    null => '',
  };
  late final TextEditingController costController = TextEditingController(
    text: openedCostText,
  );
  late final TextEditingController currencyController;
  late LinePeriod? linePeriod = opened?.line?.period;
  // As the cost: an untouched amount keeps the stored value, not its
  // rounding.
  late final String openedLineText = switch (opened?.line) {
    final HabitLine line => formatAmount(line.amount),
    null => '',
  };
  late final TextEditingController lineController = TextEditingController(
    text: openedLineText,
  );
  bool saving = false;

  // A price is in the habit's currency, else another habit's, else the
  // device region's.
  @override
  void initState() {
    super.initState();
    currencyController = TextEditingController(
      text:
          opened?.currency ??
          ref
              .read(viceListProvider)
              .value
              ?.map((Vice v) => v.currency)
              .nonNulls
              .firstOrNull ??
          deviceCurrency(),
    );
  }

  @override
  void dispose() {
    viceNameController.dispose();
    unitLabelController.dispose();
    unitSingularController.dispose();
    costController.dispose();
    currencyController.dispose();
    lineController.dispose();
    super.dispose();
  }

  HabitLine? get _line {
    final LinePeriod? period = linePeriod;
    if (period == null) return null;
    final String text = lineController.text.trim();
    final double? amount = text == openedLineText && opened?.line != null
        ? opened!.line!.amount
        : parseAmount(text)?.toDouble();
    return amount == null ? null : HabitLine(amount, period);
  }

  num get _lineTyped => parseAmount(lineController.text) ?? 0;

  // As the amount sheet's stepper: a step of one keeps a typed fraction.
  void _stepLine(int step, int direction) {
    final num typed = _lineTyped;
    final num next = step == 1
        ? typed + direction
        : direction > 0
        ? ((typed / step).floor() + 1) * step
        : ((typed / step).ceil() - 1) * step;
    lineController.text = formatAmount(next < 1 ? 1 : next);
  }

  UnitAndPrice get _unitAndPrice {
    final String label = unitLabelController.text.trim();
    final String one = unitSingularController.text.trim();
    final String costText = costController.text.trim();
    final double? cost = costText == openedCostText
        ? opened?.costPerUnit
        : parseAmount(costText)?.toDouble();
    return (
      unitLabel: label.isEmpty ? null : label,
      unitSingular: label.isEmpty || one.isEmpty ? null : one,
      costPerUnit: cost,
      currency: cost == null
          ? null
          : currencyController.text.trim().toUpperCase(),
    );
  }

  Future<void> _save(User user) async {
    // A locked vice's name and unit are placeholders, never to be saved.
    if (opened?.locked ?? false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(ViceForm.lockedMessage)));
      return;
    }
    if (!formKey.currentState!.validate() || unit == null) {
      return;
    }

    final Vice? vice = opened;
    final String name = viceNameController.text;
    final UnitAndPrice unitAndPrice = _unitAndPrice;
    final bool unitAndPriceChanged =
        vice != null && unitAndPrice != unitAndPriceOf(vice);
    final HabitLine? line = _line;
    final bool lineChanged = vice != null && line != vice.line;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // The label, price and line exist only sealed, so they wait for the key
    // too.
    if ((vice == null || unitAndPriceChanged || lineChanged) &&
        !ref.read(trackerWritesProvider).canCreate) {
      // The form stays open with what was typed.
      messenger.showSnackBar(
        const SnackBar(content: Text('Not saved. $noJournalKeyMessage')),
      );
      return;
    }

    final SentWrite? write;
    if (vice == null) {
      write = ref
          .read(trackerWritesProvider)
          .addVice(
            ownerID: user.uid,
            name: name,
            unit: unit!,
            category: category,
            unitAndPrice: unitAndPrice,
            line: line,
          );
    } else if (name != vice.name ||
        unit != vice.unit ||
        !vice.categoryStored ||
        category != vice.category ||
        unitAndPriceChanged ||
        lineChanged) {
      // Only the changed fields are written: an untouched unit may be a
      // legacy value the parser shows as the fallback.
      write = ref
          .read(trackerWritesProvider)
          .updateVice(
            vice,
            name: name == vice.name ? null : name,
            unit: unit == vice.unit ? null : unit,
            category: vice.categoryStored && category == vice.category
                ? null
                : category,
            unitAndPrice: unitAndPriceChanged ? unitAndPrice : null,
            line: lineChanged ? (line: line) : null,
          );
    } else {
      write = null;
    }

    setState(() {
      saving = true;
    });

    try {
      if (write != null &&
          !await ref
              .read(rejectedWritesProvider.notifier)
              .settle(
                write,
                vice == null
                    ? 'Not saved: the habit $name'
                    : 'Change not saved: the habit ${vice.name}',
              )) {
        messenger.showSnackBar(const SnackBar(content: Text(queuedMessage)));
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while saving a habit');
      if (mounted) {
        setState(() {
          saving = false;
        });
        messenger.showSnackBar(
          SnackBar(content: Text('Not saved. ${firestoreErrorMessage(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(userProvider).value;
    final String title = widget.vice == null ? 'Add Habit' : 'Edit Habit';

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to add a habit')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
        actions: <Widget>[
          TextButton(
            onPressed: saving ? null : () => _save(user),
            child: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: viceNameController,
                decoration: const InputDecoration(labelText: 'Habit Name'),
                validator: (String? value) =>
                    viceNameError(value, unchanged: opened?.name),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Unit>(
                initialValue: unit,
                items: Unit.values
                    .map(
                      (Unit unit) => DropdownMenuItem<Unit>(
                        value: unit,
                        child: Text(unit.plural),
                      ),
                    )
                    .toList(),
                onChanged: (Unit? value) {
                  if (value != null) {
                    setState(() {
                      unit = value;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Unit'),
                validator: (Unit? value) {
                  if (value == null) {
                    return 'Please select a unit';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: ViceForm.unitLabelKey,
                      controller: unitLabelController,
                      decoration: InputDecoration(
                        labelText: 'Own unit (optional)',
                        hintText: 'cups, mg, sessions',
                        helperText:
                            'Shown in place of ${unit?.plural ?? 'the unit'}',
                        helperMaxLines: 2,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: unitLabelError,
                    ),
                  ),
                  if (unitLabelController.text.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: ViceForm.unitSingularKey,
                        controller: unitSingularController,
                        decoration: const InputDecoration(
                          labelText: 'For one',
                          hintText: 'cup',
                          helperText: 'Optional',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: unitLabelError,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      key: ViceForm.costKey,
                      controller: costController,
                      onTapOutside: closeKeyboardOnTapOutside,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cost per unit (optional)',
                        helperText: 'For what you spend',
                        suffixText: unitLabelController.text.trim().isEmpty
                            ? null
                            : 'per ${_unitAndPrice.unitSingular ?? unitLabelController.text.trim()}',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (String? value) =>
                          value?.trim() == openedCostText
                          ? null
                          : costPerUnitError(value),
                    ),
                  ),
                  if (costController.text.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 96,
                      child: TextFormField(
                        key: ViceForm.currencyKey,
                        controller: currencyController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 3,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          counterText: '',
                        ),
                        validator: (String? value) =>
                            currencyCodePattern.hasMatch(
                              value?.trim().toUpperCase() ?? '',
                            )
                            ? null
                            : 'Use a code like GBP',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ViceCategory>(
                initialValue: category,
                items: ViceCategory.values
                    .map(
                      (ViceCategory category) => DropdownMenuItem<ViceCategory>(
                        value: category,
                        child: Text(category.label),
                      ),
                    )
                    .toList(),
                onChanged: (ViceCategory? value) {
                  if (value != null) {
                    setState(() {
                      category = value;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 20),
              _lineField(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineField(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final LinePeriod? period = linePeriod;
    final UnitAndPrice words = _unitAndPrice;
    final UnitWords units = UnitWords(
      unit ?? Unit.fallback,
      words.unitLabel,
      words.unitSingular,
    );
    final int step = AmountFields.stepFor(
      ref.watch(storedTypicalsProvider)[opened?.id],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          ViceForm.lineLabel,
          style: DialTypeScale.bodyS.copyWith(color: colors.muted),
        ),
        const SizedBox(height: DialSpace.xs),
        PillSegments<LinePeriod?>(
          segments: <({LinePeriod? value, String label, String spoken})>[
            (value: null, label: ViceForm.lineNone, spoken: 'No line'),
            for (final LinePeriod p in LinePeriod.values)
              (value: p, label: 'A ${p.name}', spoken: 'A line ${p.words}'),
          ],
          selected: period,
          onChanged: (LinePeriod? value) => setState(() {
            linePeriod = value;
            if (value != null && lineController.text.trim().isEmpty) {
              lineController.text = formatAmount(1);
            }
          }),
        ),
        if (period != null) ...<Widget>[
          const SizedBox(height: DialSpace.s),
          ListenableBuilder(
            listenable: lineController,
            builder: (BuildContext context, _) => Row(
              children: <Widget>[
                StepButton(
                  glyph: DialGlyph.minus,
                  tooltip: 'Lower line',
                  onPressed: _lineTyped > 1 ? () => _stepLine(step, -1) : null,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        key: ViceForm.lineAmountKey,
                        controller: lineController,
                        textAlign: TextAlign.center,
                        style: DialTypeScale.monoXL.copyWith(
                          fontSize: 28,
                          color: scheme.onSurface,
                        ),
                        onTapOutside: closeKeyboardOnTapOutside,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Line',
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        validator: (String? value) =>
                            value?.trim() == openedLineText &&
                                opened?.line != null
                            ? null
                            : lineAmountError(value),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${units.nameFor(_lineTyped)} ${period.words}',
                        style: DialTypeScale.bodyS.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                StepButton(
                  glyph: DialGlyph.plus,
                  tooltip: 'Raise line',
                  onPressed: () => _stepLine(step, 1),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: DialSpace.xs),
        Text(
          ViceForm.lineHelp,
          style: DialTypeScale.bodyS.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

class EditVice extends ConsumerWidget {
  const EditVice({super.key, required this.viceID});

  final String viceID;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>?> viceListValue = ref.watch(viceListProvider);
    final List<Vice>? viceList = viceListValue.value;

    if (viceList == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Habit')),
        body: switch (viceListValue.error) {
          final Object error => ErrorView(
            message: loadErrorMessage('your habits', error),
            onRetry: () =>
                ref.invalidate(viceListForUserProvider, asReload: true),
          ),
          null => const Center(child: CircularProgressIndicator()),
        },
      );
    }

    final Vice? vice = viceList.where((Vice v) => v.id == viceID).firstOrNull;

    if (vice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Habit')),
        body: const Center(child: Text('Habit not found')),
      );
    }

    return ViceForm(key: ValueKey<String>(vice.id), vice: vice);
  }
}
