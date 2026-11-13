import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

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
    super.dispose();
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // The label and price exist only sealed, so they wait for the key too.
    if ((vice == null || unitAndPriceChanged) &&
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
          );
    } else if (name != vice.name ||
        unit != vice.unit ||
        !vice.categoryStored ||
        category != vice.category ||
        unitAndPriceChanged) {
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
            ],
          ),
        ),
      ),
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
