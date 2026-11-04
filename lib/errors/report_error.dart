import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Every caught error, uncaught error and failed provider ends here. It writes
// to the device log (Console.app, `flutter logs`) in release builds too; no
// crash reporter is wired until Jack picks one (HANDOVER.md, r2-crash).
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
// Outside debug builds dumpErrorToConsole drops the context.
void reportErrorDetails(FlutterErrorDetails details) {
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
  FlutterError.onError = reportErrorDetails;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    reportError(error, stack, context: 'outside any handler');
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
