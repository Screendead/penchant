import 'package:flutter/material.dart';

class RecordNewActivityDialog extends StatelessWidget {
  const RecordNewActivityDialog({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record New Vice Activity'),
      content: const Placeholder(),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
