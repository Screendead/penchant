import 'package:flutter/material.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

class RecordNewActivityButton extends StatelessWidget {
  const RecordNewActivityButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.addchart),
      label: const Text('Record'),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return const RecordNewActivityDialog();
          },
        );
      },
    );
  }
}
