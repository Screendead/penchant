import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/vice_list_provider.dart';

class RecordNewActivityDialog extends ConsumerStatefulWidget {
  const RecordNewActivityDialog({
    super.key,
    required this.context,
  });

  final BuildContext context;

  @override
  ConsumerState<RecordNewActivityDialog> createState() =>
      _RecordNewActivityDialogState();
}

class _RecordNewActivityDialogState
    extends ConsumerState<RecordNewActivityDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  Vice? selectedVice;
  final TextEditingController dateController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  String unit = Unit.item.nameFor(0);

  String? error;

  @override
  void initState() {
    super.initState();

    final DateTime now = DateTime.now();
    dateController.text = DateFormat('dd/MM/yyyy, HH:mm').format(now);
  }

  void updateUnit(int quantity) {
    setState(() {
      unit = selectedVice == null
          ? Unit.item.nameFor(quantity)
          : selectedVice!.unit.nameFor(quantity);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice>? vices = ref.watch(viceListProvider).value;

    if (vices == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return AlertDialog(
      title: const Text('Record New Vice Activity'),
      icon: const Icon(Icons.addchart),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Vice>(
              value: selectedVice,
              isExpanded: true,
              hint: const Text('Select Vice'),
              onChanged: (Vice? value) {
                final int parsedQuantity =
                    int.tryParse(quantityController.text) ?? 0;

                setState(() {
                  selectedVice = value;
                  updateUnit(parsedQuantity);
                });
              },
              items: vices
                  .map(
                    (Vice vice) => DropdownMenuItem<Vice>(
                      value: vice,
                      child: Text(vice.name),
                    ),
                  )
                  .toList(),
              validator: (Vice? value) {
                if (value == null) {
                  return 'Please select a vice';
                }

                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: dateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date and Time',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity',
                suffixText: unit,
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a quantity';
                }

                if (int.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }

                return null;
              },
              onChanged: (String value) {
                final int parsed = int.tryParse(value) ?? 0;
                updateUnit(parsed);
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          onPressed: () async {
            if (formKey.currentState!.validate()) {
              final DateTime date =
                  DateFormat('dd/MM/yyyy, HH:mm').parse(dateController.text);

              try {
                await FirebaseFirestore.instance.collection('activities').add({
                  'createdAt': date,
                  'ownerID': FirebaseAuth.instance.currentUser!.uid,
                  'quantity': int.parse(quantityController.text),
                  'viceID': selectedVice!.id,
                });
              } on FirebaseException catch (e) {
                setState(() {
                  error = 'Error recording activity: ${e.message}';
                });

                return;
              }

              if (widget.context.mounted) {
                Navigator.of(widget.context).pop();
              }
            }
          },
          label: const Text('Record'),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
