import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracker/formats.dart';

// An activity's date and time. Live, it shows the current time and ticks;
// unlocked, the user types it or picks it.
class ActivityDateField extends StatefulWidget {
  const ActivityDateField({
    super.key,
    required this.controller,
    required this.startLive,
    this.manualSeed,
  });

  // Displays createdAt and parses it back for the write, so every screen
  // that edits an activity's date uses this one pattern.
  static DateFormat get format => entryDateFormat;

  static const String label = 'Date and Time';

  final TextEditingController controller;
  final bool startLive;

  // What the field shows on leaving live mode; without it the field keeps the
  // last time it showed.
  final DateTime Function()? manualSeed;

  @override
  State<ActivityDateField> createState() => _ActivityDateFieldState();
}

class _ActivityDateFieldState extends State<ActivityDateField> {
  static final DateTime _firstDate = DateTime(2000);
  static final DateTime _lastDate = DateTime(2100);

  late bool _live = widget.startLive;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (_live) {
      _startClock();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _showNow() {
    widget.controller.text = ActivityDateField.format.format(clock.now());
  }

  void _startClock() {
    _showNow();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _showNow());
  }

  void _toggle() {
    setState(() {
      _live = !_live;
    });
    if (_live) {
      _startClock();
    } else {
      _clock?.cancel();
      _clock = null;
      if (widget.manualSeed case final DateTime Function() seed) {
        widget.controller.text = ActivityDateField.format.format(seed());
      }
    }
  }

  // The picker asserts its initial date is in range; an unreadable legacy
  // date reads as the epoch.
  DateTime _pickerStart() {
    final DateTime shown =
        ActivityDateField.format.tryParse(widget.controller.text) ??
        clock.now();
    return shown.isBefore(_firstDate)
        ? _firstDate
        : shown.isAfter(_lastDate)
        ? _lastDate
        : shown;
  }

  Future<void> _pick() async {
    if (_live) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _pickerStart(),
      firstDate: _firstDate,
      lastDate: _lastDate,
    );

    if (date == null || !mounted) {
      return;
    }

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
    );

    if (time == null || !mounted) {
      return;
    }

    widget.controller.text = ActivityDateField.format.format(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      readOnly: _live,
      decoration: InputDecoration(
        labelText: ActivityDateField.label,
        suffixIcon: IconButton(
          tooltip: _live
              ? 'Manually enter date and time'
              : 'Use current date and time',
          icon: Icon(_live ? Icons.lock_clock : Icons.lock_open),
          onPressed: _toggle,
        ),
      ),
      validator: (String? value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a date and time';
        }

        if (ActivityDateField.format.tryParse(value) == null) {
          return 'Please enter a valid date and time';
        }

        return null;
      },
      onTap: _pick,
    );
  }
}
