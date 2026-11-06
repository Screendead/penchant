import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/bootstrap.dart';
import 'package:tracker/crypto/plaintext_migration.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/font_licence.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  registerFontLicence();
  startApp();
}

// main() without the global error handlers, which flutter_test owns.
void startApp() {
  runApp(
    const ProviderScope(
      observers: [ReportProviderErrors()],
      // Every provider reaches Firebase when first read, and nothing reads one
      // until MyApp builds, after Firebase has started.
      child: Bootstrap(initialize: initializeFirebase, child: MyApp()),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final AsyncValue<User?> userValue = ref.watch(userProvider);
    final User? user = userValue.value;

    // Swapping `home` leaves pushed routes on the stack, where the previous
    // session's pages would sit over the sign-in screen.
    ref.listen<AsyncValue<User?>>(userProvider, (previous, next) {
      if (previous?.value?.uid != next.value?.uid) {
        navigatorKey.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
      }
    });

    // Kept alive here so sealing runs whichever screen is open.
    ref.listen(plaintextMigrationProvider, (_, _) {});

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      excludeFromSemantics: true,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Penchant',
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: appLocales,
        localeListResolutionCallback: resolveAppLocale,
        // Until Auth reports the persisted session, a signed-in user would
        // otherwise see the sign-in screen; a signed-out one is AsyncData(null).
        home: user != null
            ? const Homepage()
            : userValue.hasError
            ? const AuthStateFailure()
            : !userValue.hasValue
            ? const AuthStateLoading()
            : const Authenticate(),
        onGenerateRoute: generateRoute,
        builder: (BuildContext context, Widget? child) => rejectedWritesBuilder(
          context,
          RecoveryKeyGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

class AuthStateLoading extends StatelessWidget {
  const AuthStateLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class AuthStateFailure extends ConsumerWidget {
  const AuthStateFailure({super.key});

  static const String message =
      'Could not check whether you are signed in. Try again.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: ErrorView(
          message: message,
          onRetry: () => ref.invalidate(userProvider, asReload: true),
        ),
      ),
    );
  }
}

Route<void> generateRoute(RouteSettings settings) {
  final Widget page = routePage(settings.name);
  // Forms that save or discard open as modals; pages to browse push.
  return MaterialPageRoute<void>(
    fullscreenDialog:
        page is ViceForm || page is EditVice || page is ViceActivityEditorPage,
    settings: settings,
    builder: (_) => page,
  );
}

Widget routePage(String? name) {
  final List<String> segments = Uri.parse(name ?? '').pathSegments;

  switch (segments) {
    case ['vices', 'add']:
      return const ViceForm();
    case ['vices', final String viceID, 'edit']:
      return EditVice(viceID: viceID);
    case ['vices', final String viceID, 'activities']:
      return ViceActivityHistoryPage(viceID: viceID);
    case ['vices', final String viceID, 'activities', final String activityID]:
      return ViceActivityEditorPage(viceID: viceID, activityID: activityID);
    case ['manage-data']:
      return const ManageData();
    case ['settings']:
      return const Settings();
    case ['settings', 'account']:
      return const AccountSettings();
    case ['settings', 'recovery-key']:
      return const RecoveryKeyPage();
    default:
      return const NotFound();
  }
}
