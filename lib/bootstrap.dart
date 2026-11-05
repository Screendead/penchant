import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/theme.dart';
import 'package:tracker/widgets/info_box.dart';

enum _Startup { running, failed, done }

// Shows [child] once [initialize] completes, and a retry if it throws. Without
// a first frame the native launch screen stays up, so runApp comes first.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, required this.initialize, required this.child});

  static const String failedMessage =
      'Penchant could not start. Try again, and if it keeps failing, '
      'close the app and reopen it.';

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  _Startup _startup = _Startup.running;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _retry() {
    setState(() => _startup = _Startup.running);
    _start();
  }

  Future<void> _start() async {
    _Startup outcome;
    try {
      await widget.initialize();
      outcome = _Startup.done;
    } catch (e, stack) {
      reportError(e, stack, context: 'while starting Firebase');
      outcome = _Startup.failed;
    }
    if (mounted) {
      setState(() => _startup = outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_startup == _Startup.done) {
      return widget.child;
    }

    return MaterialApp(
      title: 'Penchant',
      theme: appTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: appLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: Scaffold(
        body: SafeArea(
          child: _startup == _Startup.failed
              ? ErrorView(message: Bootstrap.failedMessage, onRetry: _retry)
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
