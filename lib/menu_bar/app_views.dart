import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// The macOS app's views: the main window's (the implicit view) shows [main],
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
    final FlutterView? main =
        WidgetsBinding.instance.platformDispatcher.implicitView;
    return ViewCollection(
      views: <Widget>[
        for (final FlutterView view
            in WidgetsBinding.instance.platformDispatcher.views)
          View(
            key: ValueKey<int>(view.viewId),
            view: view,
            child: view == main ? widget.main : widget.popover,
          ),
      ],
    );
  }
}
