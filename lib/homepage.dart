import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracker/total_units_sheet.dart';
import 'package:tracker/utils/local_file.dart';
import 'package:tracker/utils/read_data.dart';
import 'package:tracker/utils/write_data.dart';
import 'package:tracker/vices_list.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();

    updateData();
  }

  Future<void> updateData() async {
    final Map<String, dynamic> data = await readData(await localFile);
    setState(() {
      _data.clear();
      _data.addAll(data);
    });
    debugPrint('Data loaded: $_data');
  }

  void _resetAll() {
    setState(() {
      _data.clear();
    });
    writeData(_data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vice Tracker'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: updateData,
          ),
        ],
      ),
      body: Column(
        children: [
          Flexible(
            child: VicesList(
              data: _data,
              onChanged: (Map<String, dynamic> data) {
                updateData();
              },
            ),
          ),
          Flexible(
            child: TotalUnitsSheet(
              data: _data,
            ),
          ),
        ],
      ),
    );
  }
}
