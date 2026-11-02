# main awaits Firebase.initializeApp with no guard and no global error handlers

**Severity:** high

Nothing registers `FlutterError.onError`, `PlatformDispatcher.onError` or `runZonedGuarded`, and the native scaffolding catches nothing downstream: `AppDelegate.swift` is a bare pass-through and `web/index.html` loads `flutter_bootstrap.js` with no `window.onerror` listener.

If initialization throws on a bad key, a misconfigured project, or no network at first launch, the exception propagates out of `main` before `runApp` executes. On web that leaves an empty body with no UI and no message; on the native targets the launch storyboard stays on screen indefinitely because the engine never attaches to remove it.

## Evidence

- `lib/main.dart:17` — `Future<void> main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n  await Firebase.initializeApp(\n    options: DefaultFirebaseOptions.currentPlatform,\n  );\n  ...\n}`
- `ios/Runner/AppDelegate.swift:10` — `return super.application(application, didFinishLaunchingWithOptions: launchOptions)`
- `web/index.html:36` — `<script src="flutter_bootstrap.js" async></script>`
- **`grep -rn "runZonedGuarded\|PlatformDispatcher\|FlutterError.onError" lib/`** → `(no matches)`
