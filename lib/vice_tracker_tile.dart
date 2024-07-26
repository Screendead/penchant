import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tracker/utils/write_data.dart';

class ViceTrackerTile extends StatefulWidget {
  const ViceTrackerTile({
    super.key,
    required this.tag,
    required this.vice,
    required this.unitsSingular,
    required this.unitsPlural,
    required this.icon,
    required this.data,
    this.onChanged,
  });

  final String tag;
  final String vice;
  final String unitsSingular;
  final String unitsPlural;
  final IconData icon;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>>? onChanged;

  @override
  State<ViceTrackerTile> createState() => _ViceTrackerTileState();
}

class _ViceTrackerTileState extends State<ViceTrackerTile> {
  int get count => widget.data[widget.tag] as int? ?? 0;
  set count(int value) {
    setState(() {
      if (value == 0) {
        widget.data.remove(widget.tag);
      } else {
        widget.data[widget.tag] = value;
      }
    });
    writeData(widget.data).then((_) {
      widget.onChanged?.call(widget.data);
    });
    debugPrint('set ${widget.tag}. data: ${jsonEncode(widget.data)}');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(widget.icon),
      title: Text(widget.vice),
      subtitle: Text(
          '$count ${count == 1 ? widget.unitsSingular : widget.unitsPlural} today'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Add a ${widget.unitsSingular} of ${widget.vice}',
            icon: const Icon(Icons.add),
            onPressed: () {
              count++;
            },
          ),
          IconButton(
            tooltip: 'Remove a ${widget.unitsSingular} of ${widget.vice}',
            icon: const Icon(Icons.remove),
            onPressed: () {
              if (count > 0) {
                count--;
              }
            },
          ),
          IconButton(
            tooltip: 'Reset ${widget.vice} ${widget.unitsPlural}',
            icon: const Icon(Icons.delete),
            onPressed: () {
              count = 0;
            },
          ),
        ],
      ),
    );
  }
}
