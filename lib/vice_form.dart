import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
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
  bool saving = false;

  @override
  void dispose() {
    viceNameController.dispose();
    super.dispose();
  }

  Future<void> _save(User user) async {
    // A locked vice's name and unit are placeholders, never to be saved.
    if (!formKey.currentState!.validate() ||
        unit == null ||
        (opened?.locked ?? false)) {
      return;
    }

    final Vice? vice = opened;
    final String name = viceNameController.text;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final SentWrite? write;
    if (vice == null) {
      write = ref
          .read(trackerWritesProvider)
          .addVice(ownerID: user.uid, name: name, unit: unit!);
    } else if (name != vice.name || unit != vice.unit) {
      // Only the changed fields are written: an untouched unit may be a
      // legacy value the parser shows as the fallback.
      write = ref
          .read(trackerWritesProvider)
          .updateVice(
            vice,
            name: name == vice.name ? null : name,
            unit: unit == vice.unit ? null : unit,
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
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
