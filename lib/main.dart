import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_form.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();

  runApp(const ProviderScope(child: MyApp()));
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
    final User? user = ref.watch(userProvider).value;

    // Swapping `home` leaves pushed routes on the stack, where the previous
    // session's pages would sit over the sign-in screen.
    ref.listen<AsyncValue<User?>>(userProvider, (previous, next) {
      if (previous?.value?.uid != next.value?.uid) {
        navigatorKey.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
      }
    });

    return GestureDetector(
      onTap: FocusManager.instance.primaryFocus?.unfocus,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Vice Tracker',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            floatingLabelBehavior: FloatingLabelBehavior.always,
            floatingLabelAlignment: FloatingLabelAlignment.center,
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.pink),
            ),
            errorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
          ),
        ),
        home: user == null ? const Authenticate() : const Homepage(),
        onGenerateRoute: generateRoute,
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
    default:
      return const NotFound();
  }
}
