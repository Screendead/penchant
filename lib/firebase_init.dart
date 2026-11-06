import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/firebase_options.dart';

const bool useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
);

// A demo-* project has no live resources, so a call that misses the emulators
// fails instead of reaching production. tools/e2e.sh and tools/run-emulated.sh
// start the emulators under this id.
const String emulatorProjectId = 'demo-tracker';
const String emulatorHost = 'localhost';
const int authEmulatorPort = 9099;
const int firestoreEmulatorPort = 8080;

// The emulators accept any API key, but the native FirebaseInstallations,
// which firebase_core's Swift package links, aborts the app at configure
// unless the key is 39 URL-safe characters starting with A. FIROptions rejects
// a malformed app id.
const FirebaseOptions emulatorOptions = FirebaseOptions(
  apiKey: 'A-demo-key-for-the-local-emulators-only',
  appId: '1:000000000000:ios:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: emulatorProjectId,
  iosBundleId: 'com.screendead.penchant',
);

// Offline logging rests on this: the disk cache keeps queued writes across
// app restarts and answers reads with no signal. Settings apply only before
// Firestore's first use.
void _configureFirestoreCache() {
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: _firestoreCacheBytes,
  );
}

// The SDK's own default, chosen on purpose: a journal's documents are a few
// hundred bytes, so this holds well over a hundred thousand entries before the
// SDK evicts any that no listener uses.
const int _firestoreCacheBytes = 100 * 1024 * 1024;

// Collection is set on every launch: the override persists, and an emulator
// build of the same bundle ID on this device turned it off.
void _reportToCrashlytics() {
  final FirebaseCrashlytics crashlytics = FirebaseCrashlytics.instance;
  errorForwarder = crashlyticsForwarder(crashlytics.recordError);
  _setCrashlyticsCollection(true);
}

// Not awaited, and a failure is only reported: Bootstrap shows its retry
// screen when initializeFirebase throws, so a crash reporter that failed or
// hung would keep the user out of the app on every launch.
void _setCrashlyticsCollection(bool enabled) {
  unawaited(
    FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(enabled)
        .catchError((Object e, StackTrace stack) {
          reportError(
            e,
            stack,
            context: 'while setting Crashlytics collection',
          );
        }),
  );
}

typedef RecordError =
    Future<void> Function(
      dynamic exception,
      StackTrace? stack, {
      dynamic reason,
      bool? printDetails,
      bool fatal,
    });

// Sends the exception, stack and literal context only. FlutterErrorDetails'
// informationCollector is left out: its diagnostics can describe widgets,
// and a Text widget's description carries its string, a habit name.
// recordFlutterError is avoided as it prints the error a second time. A
// failed upload is dropped: reporting it would come back here.
@visibleForTesting
ErrorForwarder crashlyticsForwarder(RecordError record) =>
    (FlutterErrorDetails details, {required bool fatal}) {
      record(
        details.exception,
        details.stack,
        reason: details.context?.toDescription(),
        printDetails: false,
        fatal: fatal,
      ).ignore();
    };

Future<void> initializeFirebase() async {
  if (!useFirebaseEmulators) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _reportToCrashlytics();
    // App Attest yields no token App Check accepts until the Runner target
    // has the App Attest entitlement, which the current signing team cannot
    // sign (HANDOVER.md, "For Jack to do"). firebase_app_check 0.4.9 picks App
    // Attest whenever DCAppAttestService reports the device supports it,
    // entitlement or not, so DeviceCheck covers only devices that cannot
    // attest.
    await FirebaseAppCheck.instance.activate(
      providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    _configureFirestoreCache();
    return;
  }

  final FirebaseApp app = await Firebase.initializeApp(
    options: emulatorOptions,
  );

  // initializeApp returns an already-configured native default app when the
  // API keys match, whatever project it points at.
  if (!app.options.projectId.startsWith('demo-')) {
    throw StateError(
      'USE_FIREBASE_EMULATORS is set but the default Firebase app points at '
      '"${app.options.projectId}". Refusing to start.',
    );
  }

  // Crashlytics has no emulator. The override persists across launches and
  // takes effect from the next one; the emulator build's Info.plist
  // (tools/strip-firebase-plist.sh) covers this launch.
  _setCrashlyticsCollection(false);

  // The emulators ignore App Check. A debug token is a production credential
  // once registered in the console, so none is committed here.
  await FirebaseAppCheck.instance.activate(
    providerApple: const AppleDebugProvider(),
  );

  // The emulators lose their data on shutdown; an on-device cache would
  // outlive it.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    emulatorHost,
    firestoreEmulatorPort,
  );
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, authEmulatorPort);
}
