import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_button.dart';

import 'fakes.dart';

void main() {
  group('routes', () {
    // Every name the app pushes.
    const Map<String, Type> pages = <String, Type>{
      '/manage-data': ManageData,
      '/settings': Settings,
      '/settings/account': AccountSettings,
      '/vices/add': ViceForm,
      '/vices/v1/edit': EditVice,
      '/vices/v1/activities': ViceActivityHistoryPage,
      '/vices/v1/activities/a1': ViceActivityEditorPage,
    };

    test('each pushed name opens its page', () {
      pages.forEach((String name, Type page) {
        expect(routePage(name).runtimeType, page, reason: name);
      });
      expect(routePage('/vices/v1/delete'), isA<NotFound>());
      expect(routePage('/settings/privacy'), isA<NotFound>());
    });

    test('only the forms open as modals', () {
      final Set<String> modal = <String>{
        for (final String name in pages.keys)
          if ((generateRoute(RouteSettings(name: name)) as PageRoute<void>)
              .fullscreenDialog)
            name,
      };
      expect(modal, <String>{
        '/vices/add',
        '/vices/v1/edit',
        '/vices/v1/activities/a1',
      });
    });

    test('the edit route passes the vice id through', () {
      expect((routePage('/vices/v1/edit') as EditVice).viceID, 'v1');
    });
  });

  group('the home screen', () {
    Future<void> pumpHome(
      WidgetTester tester, [
      List<Vice> vices = const <Vice>[],
    ]) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            ...habitOverrides(vices),
            viceActivityDayProvider.overrideWith(
              (ref, DateTime day) => AsyncData(<ViceActivity>[]),
            ),
          ],
          child: const MaterialApp(
            home: Homepage(),
            onGenerateRoute: generateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('records through the Log button on Today and Record on the '
        'Graph tab', (WidgetTester tester) async {
      await pumpHome(tester, [fakeVice('coffee')]);
      expect(find.byType(LogButton), findsOneWidget);
      expect(find.byType(RecordNewActivityButton), findsNothing);

      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(find.text('Usage Graph'), findsOneWidget);
      expect(find.byType(RecordNewActivityButton), findsOneWidget);
    });

    testWidgets('a page opened from the drawer returns to a closed drawer', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage Data'));
      await tester.pumpAndSettle();
      expect(find.text('Your Habits'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ManageData), findsNothing);
      expect(find.byType(Drawer), findsNothing);
    });
  });
}
