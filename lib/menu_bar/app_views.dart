import 'dart:math' show min;
import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// The macOS app's views: the main window's shows [main],
/// and any other, which the status item's popover adds while it is open and
/// removes when it closes, shows [popover]. Providers sit above this widget,
/// so both views share them.
class AppViews extends StatefulWidget {
  const AppViews({super.key, required this.main, required this.popover});

  final Widget main;
  final Widget popover;

  @override
  State<AppViews> createState() => _AppViewsState();
}

class _AppViewsState extends State<AppViews> with WidgetsBindingObserver {
  // The engine runs with multi-view enabled (MainFlutterWindow.swift), which
  // still announces an implicit view, of size zero, that no window shows. The
  // main window's view is the first sized one; the popover's come later.
  int? _mainViewId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The engine reports a view added or removed as a metrics change.
  @override
  void didChangeMetrics() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final List<FlutterView> views = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .where((FlutterView v) => !v.physicalSize.isEmpty)
        .toList();
    if (views.isNotEmpty) {
      _mainViewId ??= views.map((FlutterView v) => v.viewId).reduce(min);
    }
    return ViewCollection(
      views: <Widget>[
        for (final FlutterView view in views)
          View(
            key: ValueKey<int>(view.viewId),
            view: view,
            child: view.viewId == _mainViewId ? widget.main : widget.popover,
          ),
      ],
    );
  }
}
