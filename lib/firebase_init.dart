import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

// The emulators accept any API key; FIROptions rejects a malformed app id.
const FirebaseOptions _emulatorOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:ios:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: emulatorProjectId,
  iosBundleId: 'com.screendead.tracker.tracker',
);

Future<void> initializeFirebase() async {
  if (!useFirebaseEmulators) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // App Attest yields no token App Check accepts until the Runner target
    // has the App Attest entitlement, which the current signing team cannot
    // sign (HANDOVER.md, "For Jack to do"). firebase_app_check 0.4.9 picks App
    // Attest whenever DCAppAttestService reports the device supports it,
    // entitlement or not, so DeviceCheck covers only devices that cannot
    // attest.
    await FirebaseAppCheck.instance.activate(
      providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    return;
  }

  final FirebaseApp app = await Firebase.initializeApp(
    options: _emulatorOptions,
  );

  // initializeApp returns an already-configured native default app when the
  // API keys match, whatever project it points at.
  if (!app.options.projectId.startsWith('demo-')) {
    throw StateError(
      'USE_FIREBASE_EMULATORS is set but the default Firebase app points at '
      '"${app.options.projectId}". Refusing to start.',
    );
  }

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
