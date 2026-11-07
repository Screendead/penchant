import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/firebase_init.dart';

void main() {
  tearDown(() => errorForwarder = null);

  test('caught errors are forwarded as non-fatal', () {
    final List<(FlutterErrorDetails, bool)> sent = [];
    errorForwarder = (FlutterErrorDetails d, {required bool fatal}) =>
        sent.add((d, fatal));

    final StackTrace stack = StackTrace.current;
    reportError(StateError('boom'), stack, context: 'while saving a habit');

    expect(sent, hasLength(1));
    expect(sent.single.$1.exception, isA<StateError>());
    expect(sent.single.$1.stack, stack);
    expect(sent.single.$1.context!.toDescription(), 'while saving a habit');
    expect(sent.single.$2, isFalse);
  });

  test('the uncaught-error handlers forward as fatal', () {
    final FlutterExceptionHandler? flutterBefore = FlutterError.onError;
    final ErrorCallback? platformBefore = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
    });
    final List<(Object, bool)> sent = [];
    errorForwarder = (FlutterErrorDetails d, {required bool fatal}) =>
        sent.add((d.exception, fatal));

    installErrorHandlers();
    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: StateError('in build'),
    );
    FlutterError.onError!(details);
    final bool handled = PlatformDispatcher.instance.onError!(
      StateError('in a zone'),
      StackTrace.current,
    );

    expect(handled, isTrue);
    expect(sent.map(((Object, bool) s) => s.$2), <bool>[true, true]);
    expect(sent.map(((Object, bool) s) => '${s.$1}'), <String>[
      'Bad state: in build',
      'Bad state: in a zone',
    ]);
  });

  test('Crashlytics gets the exception, stack and context, nothing else', () {
    final List<Map<String, Object?>> calls = [];
    final ErrorForwarder forward = crashlyticsForwarder((
      dynamic exception,
      StackTrace? stack, {
      dynamic reason,
      bool? printDetails,
      bool fatal = false,
    }) async {
      calls.add(<String, Object?>{
        'exception': exception,
        'stack': stack,
        'reason': reason,
        'printDetails': printDetails,
        'fatal': fatal,
      });
    });

    final StateError error = StateError('boom');
    final StackTrace stack = StackTrace.current;
    forward(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        context: ErrorDescription('while recording an activity'),
        informationCollector: () => <DiagnosticsNode>[
          ErrorDescription('Text("Coffee")'),
        ],
      ),
      fatal: true,
    );

    expect(calls, <Map<String, Object?>>[
      <String, Object?>{
        'exception': error,
        'stack': stack,
        'reason': 'while recording an activity',
        'printDetails': false,
        'fatal': true,
      },
    ]);
  });

  test('a failed upload is dropped rather than reported again', () async {
    final ErrorForwarder forward = crashlyticsForwarder(
      (
        dynamic exception,
        StackTrace? stack, {
        dynamic reason,
        bool? printDetails,
        bool fatal = false,
      }) => Future<void>.error(StateError('upload failed')),
    );

    forward(FlutterErrorDetails(exception: StateError('boom')), fatal: false);
    await pumpEventQueue();
  });
}
