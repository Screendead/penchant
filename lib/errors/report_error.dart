import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Where each error goes after the device log: Crashlytics in production
// (firebase_init.dart), nothing under the emulators or in tests. Callers pass
// only literal context strings, so no habit name or amount reaches it.
typedef ErrorForwarder =
    void Function(FlutterErrorDetails details, {required bool fatal});

ErrorForwarder? errorForwarder;

// Every caught error, uncaught error and failed provider ends here. It writes
// to the device log (Console.app, `flutter logs`) in release builds too.
void reportError(Object error, StackTrace? stack, {required String context}) {
  reportErrorDetails(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'tracker',
      context: ErrorDescription(context),
    ),
  );
}

// Must not call FlutterError.reportError: FlutterError.onError ends here.
void reportErrorDetails(FlutterErrorDetails details, {bool fatal = false}) {
  _log(details);
  errorForwarder?.call(details, fatal: fatal);
}

// Outside debug builds dumpErrorToConsole drops the context.
void _log(FlutterErrorDetails details) {
  if (kDebugMode) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
    return;
  }
  final String label =
      'Error ${details.context?.toDescription() ?? 'thrown'}: '
      '${details.exceptionAsString()}';
  if (details.stack == null) {
    debugPrint(label);
  } else {
    debugPrintStack(stackTrace: details.stack, label: label, maxFrames: 100);
  }
}

// Installed from main() only: flutter_test owns both handlers in tests.
void installErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) =>
      reportErrorDetails(details, fatal: true);
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    reportErrorDetails(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'tracker',
        context: ErrorDescription('outside any handler'),
      ),
      fatal: true,
    );
    return true;
  };
}

// A stream provider's error reaches only the widgets watching it, so this
// copies each one to the log.
final class ReportProviderErrors extends ProviderObserver {
  const ReportProviderErrors();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    reportError(
      error,
      stackTrace,
      context: 'in ${context.provider.name ?? context.provider}',
    );
  }
}
