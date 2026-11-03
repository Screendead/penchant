import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/add_vice.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/crypto/journal_key_provider.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/journal_key/journal_gate.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/theme.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  // Logged as "E2EE native AES-GCM: ..." for the e2e run to check.
  final NativeAesReport aes = await checkNativeAesGcm(
    nativeAesGcm(secretKeyLength: 32),
  );

  runApp(
    ProviderScope(
      overrides: [nativeAesReportProvider.overrideWithValue(aes)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? user = ref.watch(userProvider).value;

    return GestureDetector(
      onTap: FocusManager.instance.primaryFocus?.unfocus,
      child: MaterialApp(
        title: 'Vice Tracker',
        theme: appTheme(),
        home: user == null
            ? const Authenticate()
            : const JournalGate(child: Homepage()),
        onGenerateRoute: (RouteSettings settings) {
          final Uri uri = Uri.parse(settings.name ?? '');

          if (uri.pathSegments.length == 3 &&
              uri.pathSegments[0] == 'vices' &&
              uri.pathSegments[2] == 'activities') {
            return MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (BuildContext context) {
                return ViceActivityHistoryPage(viceID: uri.pathSegments[1]);
              },
            );
          }

          if (uri.pathSegments.length == 4 &&
              uri.pathSegments[0] == 'vices' &&
              uri.pathSegments[2] == 'activities') {
            return MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (BuildContext context) {
                return ViceActivityEditorPage(
                  viceID: uri.pathSegments[1],
                  activityID: uri.pathSegments[3],
                );
              },
            );
          }

          return MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (BuildContext context) {
              switch (settings.name) {
                case '/manage-data':
                  return const ManageData();
                case '/vices/add':
                  return const AddVice();
                case '/settings':
                  return const Settings();
                case '/settings/account':
                  return const AccountSettings();
                case '/settings/recovery-key':
                  return const RecoveryKeySettingsRoute();
                default:
                  return const NotFound();
              }
            },
          );
        },
      ),
    );
  }
}
