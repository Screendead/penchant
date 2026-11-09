import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_form.dart';

import 'package:tracker/deleted_habit_page.dart';

import 'fake_account.dart';
import 'fakes.dart';

void main() {
  group('routes', () {
    // Every name the app pushes.
    const Map<String, Type> pages = <String, Type>{
      '/manage-data': ManageData,
      '/deleted-habit': DeletedHabitPage,
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

  testWidgets('Settings > Account opens Account Settings', (
    WidgetTester tester,
  ) async {
    final FakeUser user = FakeUser(ownerID, email: 'me@example.com');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWithValue(FakeAccount()),
          userProvider.overrideWith((ref) => Stream.value(user)),
          userProfileProvider.overrideWith((ref) => Stream.value(user)),
        ],
        child: const MaterialApp(
          home: Settings(),
          onGenerateRoute: generateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSettings), findsOneWidget);
    expect(find.byType(NotFound), findsNothing);
  });

  group('the home screen', () {
    // One habit by default: an account with none gets the onboarding.
    Future<void> pumpHome(WidgetTester tester, [List<Vice>? vices]) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            ...habitOverrides(vices ?? <Vice>[fakeVice('coffee')]),
            viceActivityDayProvider.overrideWith(
              (ref, DateTime day) => AsyncData(<ViceActivity>[]),
            ),
            viceActivityGraphProvider.overrideWith(
              (ref, ViceActivityGraphQuery query) =>
                  AsyncData(<ViceActivity>[]),
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

    testWidgets('the Penchant menu reaches Habits and Settings, and a page '
        'opened from it returns to Today with the menu shut', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      await tester.tap(find.byKey(Homepage.menuKey));
      await tester.pumpAndSettle();
      expect(find.text(Homepage.settingsItem), findsOneWidget);
      await tester.tap(find.text(Homepage.habitsItem));
      await tester.pumpAndSettle();
      expect(find.byType(ManageData), findsOneWidget);
      expect(find.text(ManageData.title), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ManageData), findsNothing);
      expect(find.text(Homepage.habitsItem), findsNothing);

      await tester.tap(find.byKey(Homepage.menuKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Homepage.settingsItem));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('the menu button is one labelled, 44 pt screen-reader stop', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);
      final SemanticsData menu = tester
          .getSemantics(find.byKey(Homepage.menuKey))
          .getSemanticsData();
      expect(menu.label, Homepage.menuLabel);
      expect(menu.hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester.getSize(find.byKey(Homepage.menuKey)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });
}
