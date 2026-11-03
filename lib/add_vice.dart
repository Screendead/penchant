import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';

class AddVice extends ConsumerStatefulWidget {
  const AddVice({super.key});

  @override
  ConsumerState<AddVice> createState() => _AddViceState();
}

class _AddViceState extends ConsumerState<AddVice> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  TextEditingController viceNameController = TextEditingController();
  Unit? unit;

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(userProvider).value;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to add a vice'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Vice'),
        actions: <Widget>[
          TextButton(
            child: const Text('Save'),
            onPressed: () async {
              if (formKey.currentState!.validate() && unit != null) {
                try {
                  await ref
                      .read(trackerWritesProvider)
                      .addVice(
                        ownerID: user.uid,
                        name: viceNameController.text,
                        unit: unit!,
                      );

                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                } on FirebaseException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message!),
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              TextFormField(
                controller: viceNameController,
                decoration: const InputDecoration(
                  labelText: 'Vice Name',
                ),
                validator: viceNameError,
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
                decoration: const InputDecoration(
                  labelText: 'Unit',
                ),
                validator: (Unit? value) {
                  if (value == null) {
                    return 'Please select a unit';
                  }

                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
