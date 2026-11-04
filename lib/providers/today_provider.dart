import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';

// The start of the current local day, moving on at midnight. iOS suspends
// timers in the background, so a resume recomputes it too.
final todayProvider = NotifierProvider<Today, DateTime>(Today.new);

class Today extends Notifier<DateTime> {
  Timer? _midnight;

  @override
  DateTime build() {
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: _refresh,
    );
    ref.onDispose(() {
      _midnight?.cancel();
      lifecycle.dispose();
    });
    return _arm();
  }

  DateTime _arm() {
    final DateTime now = DateTime.now();
    final DateTime today = startOfDay(now);
    _midnight?.cancel();
    _midnight = Timer(addDays(today, 1).difference(now), _refresh);
    return today;
  }

  void _refresh() {
    state = _arm();
  }

  @override
  bool updateShouldNotify(DateTime previous, DateTime next) => previous != next;
}
