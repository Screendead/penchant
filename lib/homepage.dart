import 'package:flutter/material.dart';
import 'package:tracker/total_units_sheet.dart';
import 'package:tracker/vices_list.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vice Tracker'),
      ),
      body: const Column(
        children: [
          Flexible(
            child: VicesList(),
          ),
          Flexible(
            child: TotalUnitsSheet(),
          ),
        ],
      ),
    );
  }
}
