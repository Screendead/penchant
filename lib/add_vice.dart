import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/writes/settle_write.dart';

class AddVice extends ConsumerStatefulWidget {
  const AddVice({super.key});

  @override
  ConsumerState<AddVice> createState() => _AddViceState();
}

class _AddViceState extends ConsumerState<AddVice> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  TextEditingController viceNameController = TextEditingController();
  Unit? unit;
  bool saving = false;

  Future<void> _save(User user) async {
    if (!formKey.currentState!.validate() || unit == null) {
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      saving = true;
    });

    try {
      final bool synced = await settleWrite(
        ref
            .read(trackerWritesProvider)
            .addVice(
              ownerID: user.uid,
              name: viceNameController.text,
              unit: unit!,
            ),
      );
      if (!synced) {
        messenger.showSnackBar(const SnackBar(content: Text(queuedMessage)));
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
        });
        messenger.showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(userProvider).value;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to add a vice')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Vice'),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              TextFormField(
                controller: viceNameController,
                decoration: const InputDecoration(labelText: 'Vice Name'),
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
                decoration: const InputDecoration(labelText: 'Unit'),
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
