import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// Adds a vice, or with [vice] edits that one.
class ViceForm extends ConsumerStatefulWidget {
  const ViceForm({super.key, this.vice});

  final Vice? vice;

  @override
  ConsumerState<ViceForm> createState() => _ViceFormState();
}

class _ViceFormState extends ConsumerState<ViceForm> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController viceNameController = TextEditingController(
    text: widget.vice?.name,
  );
  late Unit? unit = widget.vice?.unit;

  @override
  void dispose() {
    viceNameController.dispose();
    super.dispose();
  }

  Future<void> _save(User user) async {
    if (!formKey.currentState!.validate() || unit == null) {
      return;
    }

    final Vice? vice = widget.vice;
    final String name = viceNameController.text;

    try {
      if (vice == null) {
        await ref
            .read(trackerWritesProvider)
            .addVice(ownerID: user.uid, name: name, unit: unit!);
      } else if (name != vice.name || unit != vice.unit) {
        // Only the changed fields are written: an untouched unit may be a
        // legacy value the parser shows as the fallback.
        await ref
            .read(trackerWritesProvider)
            .updateVice(
              vice.id,
              name: name == vice.name ? null : name,
              unit: unit == vice.unit ? null : unit,
            );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(userProvider).value;
    final String title = widget.vice == null ? 'Add Vice' : 'Edit Vice';

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to add a vice')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          TextButton(child: const Text('Save'), onPressed: () => _save(user)),
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
                validator: (String? value) =>
                    viceNameError(value, unchanged: widget.vice?.name),
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
        appBar: AppBar(title: const Text('Edit Vice')),
        body: Center(
          child: viceListValue.hasError
              ? Text('Unable to load your vices: ${viceListValue.error}')
              : const CircularProgressIndicator(),
        ),
      );
    }

    final Vice? vice = viceList.where((Vice v) => v.id == viceID).firstOrNull;

    if (vice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Vice')),
        body: const Center(child: Text('Vice not found')),
      );
    }

    return ViceForm(key: ValueKey<String>(vice.id), vice: vice);
  }
}
