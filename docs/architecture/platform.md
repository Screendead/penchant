# Platform and native wiring: macOS helpers, Swift packages, Firebase setup, API key, auth fields

**Mac background sync.** Penchant.app embeds two helpers at `Contents/Library/LoginItems`, each its own target in
`macos/Runner.xcodeproj`: `PenchantMenuBar` (`com.screendead.penchant.menubar`, the login-item menu bar app) and
`PenchantSync` (`com.screendead.penchant.sync`, `tools/add-mac-sync-target.rb`). With Penchant closed, the menu bar
helper launches PenchantSync to write the widgets' queued logs: `LSBackgroundOnly`, prohibited activation, a headless
`FlutterEngine` on `macSyncFlushMain` (`lib/main.dart`) over the enclosing app's `App.framework` and `FlutterMacOS.framework`. It
links the plugins itself, copies `GoogleService-Info.plist` with the strip phase, and has no Crashlytics upload phase.
Its entitlements files copy Runner's, keychain group included, so that it reads the Auth session and journal key (not
yet confirmed in a signed build). Its sandbox container is its own, out of reach of sign-out's clearing, so that entry
point keeps Firestore's cache in memory (`initializeFirebase(diskCache: false)`) and the write journal in memory
(`memoryJournal()`): nothing of the user's outlives a run. A log leaves the App Group queue only once the server
acknowledges it, so a run ending offline leaves it for the next. Its bundle ID is not among those the client API key allows (Client API key). While it runs, the app's `pendingLogs` answers
empty and the app flushes once it quits (`SyncApp`, `ios/Runner/WidgetBridge.swift`). Penchant itself is a regular app
that never activates itself.

**Native dependencies come from Swift Package Manager, with no CocoaPods on either platform.** Every native plugin
ships a `Package.swift`, so there is no Podfile. `pubspec.yaml` sets `flutter: config: enable-swift-package-manager:
true`, beating a user-wide `flutter config --no-enable-swift-package-manager` (this machine has one). Flutter
generates `<platform>/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` (untracked), linked by the Runner
target; the Runner scheme's "Run Prepare Flutter Framework Script" pre-action is part of that wiring. FlutterFire's
`Package.swift` files pin `firebase-ios-sdk` `exact:`, so it moves only with a pub upgrade of the Firebase plugins:
12.19.3 now, never lower (the eMudhra CA fix, #56). Transitive pins (gRPC, abseil, GoogleUtilities, ...) are in the
tracked `Package.resolved` under `<platform>/Runner.xcworkspace/xcshareddata/swiftpm/` (what `flutter build` builds)
and its twin under `Runner.xcodeproj/project.xcworkspace/` (what Flutter's prefetch writes);
`test/apple_dependencies_test.dart` checks they match and the floor. A new plugin without a `Package.swift` makes
Flutter fall back to CocoaPods and write a Podfile, failing that test: keep the Podfile, name the plugin here, change
the test.

**Client API key.** One Firebase client key serves iOS and macOS and appears twice by design: in each
`GoogleService-Info.plist` (read by the native SDK before Dart runs) and in `lib/firebase_options.dart` (FlutterFire's
output, read by Dart's `initializeApp`). Removing either breaks one side; regenerating either file restores it. It is
a public identifier: Firebase says such keys "do not need to be treated as secrets" and are "OK to include in code or
checked-in config files", provided the key is restricted to Firebase APIs and setup follows the page's guidelines
(https://firebase.google.com/docs/projects/api-keys). Today Firestore rules are the protection (App Check: Emulator
wiring). The key's restrictions live in the production project's Google Cloud console, which Claude does not touch and
repo files cannot show. Seen there by Jack on 2026-11-09: the key Firebase made on 2026-11-05 allows the iOS app
`com.screendead.penchant` only and 8 APIs (Cloud Firestore, Cloud Datastore, Cloud Logging, Firebase App Check,
Firebase Installations, Firebase Management, Identity Toolkit, Token Service); the macOS app uses it under the same
bundle ID. Google notes the bundle-ID check
is easy to bypass, so it stops only casual reuse (https://docs.cloud.google.com/docs/authentication/api-keys). The
other key, "Auth email links - do not delete" (HTTP referrers), serves the auth email links; the old
`com.screendead.tracker.tracker` key no longer appears. Never commit a service-account file or `privateKey.json`;
`admin/.gitignore` and the root `.gitignore` exclude them.

**Emulator wiring.** `lib/firebase_init.dart` does all Firebase setup. Without the `USE_FIREBASE_EMULATORS`
dart-define it is the original `initializeApp` against production; with it, the default app gets `demo-tracker`
options, Firestore persistence is off, Auth and Firestore point at `localhost`, and startup throws if the default app
resolves to a non-`demo-` project. App Check is activated right after `initializeApp` in production only, with App
Attest and the DeviceCheck fallback (`r3-attest`: as built), and enforced nowhere; flagged builds never activate it,
since the emulators check no App Check token (Jack, 2026-11-07). It protects nothing until App Attest tokens are
accepted and enforcement is on, and App Attest yields no accepted token until the Runner target carries the App Attest
entitlement, which the current signing team cannot sign (HANDOVER.md). On iOS and macOS, firebase_core configures the
native default app from the bundled `GoogleService-Info.plist` before Dart runs, so each Runner target's "Strip
Firebase plist for emulators" build phase (`tools/strip-firebase-plist.sh`) moves it out of the bundle for flagged
builds and sets `FirebaseCrashlyticsCollectionEnabled` false in the built `Info.plist`. Crashlytics has no emulator:
production turns collection on and points `errorForwarder` (`lib/errors/report_error.dart`, where every reported error
goes after the device log) at it, uncaught errors as fatal and caught ones as non-fatal, with the literal context and
nothing the user typed; flagged builds turn it off and forward nothing. Each Runner's last build phase
(`tools/crashlytics-upload-symbols.sh`) uploads dSYMs for production release builds only.

**Native auth fields on macOS.** Flutter's macOS text input has no real AutoFill: the engine's
`shell/platform/darwin/macos/framework/Source/FlutterTextInputPlugin.mm` only sets an `NSTextContentType` on a
zero-frame `NSTextView`, with no autofill groups or `finishAutofillContext`, so Passwords never offers to fill. On
macOS the sign-in form's Email and Password `AuthField`s (those with a `nativeKind`) are an `NSTextField`
(`.username`) and an `NSSecureTextField` (`.password`, or `.newPassword` on macOS 14+ when registering), sibling
subviews of one `AppKitView` (`macos/Runner/AuthFieldPlatformView.swift`, `lib/widgets/native_auth_field.dart`); as
two platform views, a fill from Email left Password empty. `NativeAuthFieldsHost` wraps both `AuthField`s, which
still draw pills, glyphs, eye and error lines in Flutter; after each frame it lays the view over their measured text
areas (no wider than Password's, so the eye stays a Flutter button) and sends each rect to native. One method
channel, `penchant/auth_fields/<view id>`; every call names its field (`email` or `password`). Native reports text
(both fields' changes in one `changed`), Return, Tab and focus; Tab and Return from Email to Password stay in AppKit.
It never reads `stringValue` mid-edit (that commits the editor, mid-AutoFill); Dart requests native focus only when
Flutter focus came from elsewhere. Confirm password stays Flutter. Tests run as non-macOS and get the Flutter fields;
`debugUseNativeAuthFields` forces the native path. iOS keeps the Flutter fields, whose AutoFill works.
