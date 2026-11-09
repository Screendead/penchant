import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/font_licence.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_day.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fake_account.dart';
import 'fake_writes.dart';
import 'fakes.dart';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final double la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final DateTime _today = startOfDay(DateTime.now());

Vice _vice(String id, String name, int day, {bool archived = false}) => Vice(
  id: id,
  name: name,
  unit: Unit.item,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, day)),
  archived: archived,
);

final List<Vice> _vices = [
  _vice('coffee', 'Coffee', 1),
  _vice('walk', 'Late nights', 2),
  _vice('sweets', 'Sweets', 3),
  _vice('scroll', 'Doomscrolling', 4, archived: true),
];

final List<ViceActivity> _activities = [
  fakeActivity('coffee', 2, _today.add(const Duration(hours: 8))),
  fakeActivity('walk', 1, _today.add(const Duration(hours: 1))),
  fakeActivity('sweets', 3, _today.add(const Duration(hours: 15))),
];

List<Override> _overrides({bool empty = false}) {
  final List<ViceActivity> activities = empty ? [] : _activities;
  final User user = FakeUser(ownerID);
  return [
    userProvider.overrideWith((ref) => Stream.value(user)),
    userProfileProvider.overrideWith((ref) => Stream.value(user)),
    offlineProvider.overrideWith((ref) => Stream.value(false)),
    accountProvider.overrideWithValue(FakeAccount()),
    exportShareProvider.overrideWithValue(FakeExportShare()),
    trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
    memoryJournal(),
    packageInfoProvider.overrideWith(
      (ref) async => PackageInfo(
        appName: 'tracker',
        packageName: 'tracker',
        version: '0.1.0',
        buildNumber: '1',
      ),
    ),
    viceListProvider.overrideWith((ref) => AsyncData(_vices)),
    unarchivedViceListProvider.overrideWith(
      (ref) => AsyncData([
        for (final Vice v in _vices)
          if (!v.archived) v,
      ]),
    ),
    viceActivityDayProvider.overrideWith(
      (ref, DateTime day) => AsyncData(activities),
    ),
    viceActivityGraphProvider.overrideWith(
      (ref, query) => AsyncData(activities),
    ),
    viceActivityHistoryProvider.overrideWith(
      (ref, query) => AsyncData(activities),
    ),
    viceActivityProvider.overrideWith(
      (ref, String id) => AsyncData(activities.isEmpty ? null : activities[0]),
    ),
    activityTotalCountProvider.overrideWithValue(const AsyncLoading()),
    viceActivityCountProvider.overrideWith(
      (ref, String id) =>
          const AsyncData((count: 12, source: CountSource.server)),
    ),
  ];
}

Future<void> _loadFonts() async {
  for (final (String family, String file) in [
    (DialFonts.display, 'RedHatDisplay'),
    (DialFonts.text, 'RedHatText'),
    (DialFonts.mono, 'RedHatMono'),
  ]) {
    final FontLoader loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/fonts/$file-Variable.ttf'));
    await loader.load();
  }
}

// An iPhone SE-sized screen, the smallest the app runs on.
void _usePhone(WidgetTester tester, Brightness brightness) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(375 * 2, 667 * 2);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

Future<void> _pumpThemed(
  WidgetTester tester,
  Brightness brightness,
  String route, {
  bool empty = false,
}) async {
  _usePhone(tester, brightness);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(empty: empty),
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: route == '/' ? const Homepage() : routePage(route),
        onGenerateRoute: generateRoute,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(_loadFonts);

  test('the bundled fonts are loaded, with tabular figures', () {
    double width(String text, TextStyle style) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    final TextStyle body = appTheme(Brightness.light).textTheme.bodyMedium!;
    // The test font draws every glyph as a square of the font size.
    expect(width('iiii', body), lessThan(width('WWWW', body)));
    expect(width('1111', body), width('0000', body));
    expect(
      width('1111', body.copyWith(fontFeatures: const <FontFeature>[])),
      lessThan(
        width('0000', body.copyWith(fontFeatures: const <FontFeature>[])),
      ),
    );
  });

  test('the licence page lists the fonts under the OFL', () async {
    registerFontLicence();
    final List<LicenseEntry> fonts = <LicenseEntry>[
      for (final LicenseEntry entry in await LicenseRegistry.licenses.toList())
        if (entry.packages.contains(DialFonts.text)) entry,
    ];
    expect(fonts, hasLength(1));
    expect(
      fonts.single.packages,
      containsAll(<String>[DialFonts.display, DialFonts.mono]),
    );
    expect(
      fonts.single.paragraphs.map((LicenseParagraph p) => p.text).join('\n'),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );
  });

  test('colours come from lib/design, not literals in the screens', () {
    final RegExp literal = RegExp(
      r'\bColors\.(?!transparent\b)|\bColor\(\s*0[xX]|\bColor\.from',
    );
    final List<String> found = <String>[
      for (final FileSystemEntity f in Directory(
        'lib',
      ).listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.startsWith('lib/design/'))
          for (final (int i, String line) in f.readAsLinesSync().indexed)
            if (literal.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
    ];
    expect(found, isEmpty);
  });

  group('the app', () {
    List<Override> signedOut() => [
      userProvider.overrideWith((ref) => Stream.value(null)),
    ];

    testWidgets('has a light and a dark theme and follows the system', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(overrides: signedOut(), child: const MyApp()),
      );
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(app.themeMode, ThemeMode.system);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);
    });

    for (final Brightness brightness in Brightness.values) {
      testWidgets('signs in on ${brightness.name} paper when the system is '
          '${brightness.name}', (WidgetTester tester) async {
        _usePhone(tester, brightness);
        await tester.pumpWidget(
          ProviderScope(overrides: signedOut(), child: const MyApp()),
        );
        await tester.pumpAndSettle();

        final BuildContext context = tester.element(find.text('Sign in').last);
        expect(Theme.of(context).brightness, brightness);
        expect(
          tester
                  .widget<Scaffold>(find.byType(Scaffold).first)
                  .backgroundColor ??
              Theme.of(context).scaffoldBackgroundColor,
          DialPalette.of(brightness).bg,
        );
      });
    }
  });

  for (final Brightness brightness in Brightness.values) {
    final DialPalette p = DialPalette.of(brightness);
    final ThemeData theme = appTheme(brightness);
    final ColorScheme scheme = theme.colorScheme;

    group('the ${brightness.name} theme', () {
      test('is built from the tokens', () {
        expect(theme.brightness, brightness);
        expect(theme.scaffoldBackgroundColor, p.bg);
        expect(scheme.primary, p.accent);
        expect(scheme.onPrimary, p.onAccent);
        expect(scheme.surface, p.bg);
        expect(scheme.onSurface, p.text);
        expect(scheme.onSurfaceVariant, p.muted);
        expect(scheme.error, p.danger);
        expect(scheme.errorContainer, p.dangerContainer);
        expect(scheme.scrim, p.scrim);
        expect(theme.extension<DialColors>()!.data, p.data);
        expect(theme.extension<DialColors>()!.clear, p.clear);
        expect(theme.extension<DialType>()!.monoM.color, p.text);
        expect(theme.textTheme.bodyMedium!.fontFamily, DialFonts.text);
        expect(theme.textTheme.headlineLarge!.fontFamily, DialFonts.display);
        expect(
          theme.inputDecorationTheme.focusedBorder!.borderSide.color,
          p.accent,
        );
      });

      test('draws the edges that identify a control in outline', () {
        expect(scheme.outline, p.outline);
        expect(theme.inputDecorationTheme.border!.borderSide.color, p.outline);
        expect(
          theme.inputDecorationTheme.enabledBorder!.borderSide.color,
          p.outline,
        );
        expect(
          theme.outlinedButtonTheme.style!.side!
              .resolve(<WidgetState>{})!
              .color,
          p.outline,
        );
        expect(theme.bottomSheetTheme.dragHandleColor, p.outline);
        expect(theme.sliderTheme.inactiveTrackColor, p.outline);
      });

      test('rings a focused button in accent', () {
        const Set<WidgetState> focused = <WidgetState>{WidgetState.focused};
        final BorderSide ring = theme.filledButtonTheme.style!.side!.resolve(
          focused,
        )!;
        expect(ring.color, p.accent);
        expect(ring.width, 2);
        // A 2px stroke centred 3px outside: the system's 2px offset.
        expect(ring.strokeOffset / 2, 3);
        expect(
          theme.filledButtonTheme.style!.side!.resolve(<WidgetState>{}),
          isNull,
        );
        for (final ButtonStyle style in <ButtonStyle>[
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.iconButtonTheme.style!,
        ]) {
          expect(style.side!.resolve(focused)!.color, p.accent);
          expect(style.side!.resolve(focused)!.width, 2);
        }
        expect(_contrast(p.accent, p.bg), greaterThanOrEqualTo(3));
        expect(_contrast(p.accent, p.surface), greaterThanOrEqualTo(3));
      });

      test("marks the time picker's selection in accent", () {
        final TimePickerThemeData t = theme.timePickerTheme;
        // Material's pickers sit on surfaceContainerHigh.
        final Color dialog = scheme.surfaceContainerHigh;
        const Set<WidgetState> selected = <WidgetState>{WidgetState.selected};
        Color resolve(Color c, Set<WidgetState> s) =>
            WidgetStateProperty.resolveAs(c, s);
        final Color on = resolve(t.hourMinuteColor!, selected);
        final Color off = resolve(t.hourMinuteColor!, <WidgetState>{});
        expect(on, p.accent);
        expect(_contrast(on, off), greaterThanOrEqualTo(3));
        expect(_contrast(on, dialog), greaterThanOrEqualTo(3));
        expect(
          _contrast(resolve(t.hourMinuteTextColor!, selected), on),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(resolve(t.hourMinuteTextColor!, <WidgetState>{}), off),
          greaterThanOrEqualTo(4.5),
        );
        // A focused input field keeps its surface fill, so the cursor shows.
        expect(
          resolve(t.hourMinuteColor!, <WidgetState>{
            WidgetState.selected,
            WidgetState.focused,
          }),
          p.surface,
        );
        expect(resolve(t.dayPeriodColor!, selected), p.accent);
        expect(
          _contrast(resolve(t.dayPeriodTextColor!, <WidgetState>{}), dialog),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          t.inputDecorationTheme!.enabledBorder!.borderSide.color,
          p.outline,
        );
        expect(t.inputDecorationTheme!.hintStyle!.color, p.muted);
        expect(
          _contrast(theme.datePickerTheme.subHeaderForegroundColor!, dialog),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('gives no ColorScheme role a habit colour', () {
        final Set<Color> roles = <Color>{
          scheme.primary,
          scheme.secondary,
          scheme.secondaryContainer,
          scheme.tertiary,
          scheme.tertiaryContainer,
          scheme.surface,
          scheme.outline,
          scheme.inverseSurface,
        };
        expect(roles.intersection(p.data.toSet()), isEmpty);
      });

      test('pairs every text role with its ground at 4.5:1 or better', () {
        final Map<String, (Color, Color)> pairs = <String, (Color, Color)>{
          'text on bg': (p.text, p.bg),
          'text on surface': (p.text, p.surface),
          'muted on bg': (p.muted, p.bg),
          'muted on surface2': (p.muted, p.surface2),
          'onPrimary on primary': (scheme.onPrimary, scheme.primary),
          'onError on error': (scheme.onError, scheme.error),
          'onErrorContainer': (scheme.onErrorContainer, scheme.errorContainer),
          'onTertiaryContainer': (
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          ),
          'onSecondaryContainer': (
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          'clearInk on clear': (p.clearInk, p.clear),
          'snack text': (
            theme.snackBarTheme.contentTextStyle!.color!,
            theme.snackBarTheme.backgroundColor!,
          ),
          for (int i = 0; i < 5; i++)
            'data${i + 1}Ink on bg': (p.dataInk[i], p.bg),
          for (int i = 0; i < 5; i++)
            'wedgeInk on data${i + 1}': (p.wedgeInk, p.data[i]),
        };
        pairs.forEach((String name, (Color, Color) pair) {
          expect(
            _contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: name,
          );
        });
      });

      testWidgets('the clear day says so in the sage ink', (
        WidgetTester tester,
      ) async {
        await _pumpThemed(tester, brightness, '/', empty: true);

        for (final String text in <String>[
          ClearDay.headline,
          ClearDay.subline(isToday: true),
        ]) {
          expect(tester.widget<Text>(find.text(text)).style!.color, p.clearInk);
        }
      });

      // Each screen renders in Red Hat at the smallest phone size without an
      // overflow or other error.
      for (final (String name, String route, String shows) in [
        ('Today', '/', 'Today'),
        ('Manage Data', '/manage-data', 'Sweets'),
        ('Settings', '/settings', 'About'),
        ('Account Settings', '/settings/account', 'someone@example.com'),
        ('Add Habit', '/vices/add', 'Unit'),
        ('Edit Habit', '/vices/coffee/edit', 'Coffee'),
        ('history', '/vices/coffee/activities', 'Coffee'),
        ('the entry editor', '/vices/coffee/activities/a1', 'Quantity'),
      ]) {
        testWidgets('renders $name', (WidgetTester tester) async {
          await _pumpThemed(tester, brightness, route);
          expect(tester.takeException(), isNull);
          expect(find.textContaining(shows), findsWidgets);
          expect(
            Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
            brightness,
          );
        });
      }

      testWidgets('renders the Trends sheet and a day opened from it', (
        WidgetTester tester,
      ) async {
        await _pumpThemed(tester, brightness, '/');
        await tester.tap(find.text(TrendsSheet.title));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.byType(TrendsChart), findsOneWidget);
        final Rect chart = tester.getRect(find.byType(LineChart));
        await tester.tapAt(Offset(chart.right - 2, chart.center.dy));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(TrendsDay), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders the record dialog', (WidgetTester tester) async {
        await _pumpThemed(tester, brightness, '/');
        await tester.tap(find.byType(LogButton));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.longPress(
          find.descendant(
            of: find.byKey(const ValueKey<String>('fan-wedge-coffee')),
            matching: find.text('Coffee'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.byType(RecordNewActivityDialog), findsOneWidget);
      });

      testWidgets('renders sign-in and registration', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, brightness);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [userProvider.overrideWith((ref) => Stream.value(null))],
            child: const MyApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(Authenticate.registerTab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('shows a snackbar in the inverted pill', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            darkTheme: appTheme(Brightness.dark),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Logged 1 item'),
                      action: SnackBarAction(label: 'Undo', onPressed: () {}),
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pumpAndSettle();

        final Material bar = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(bar.color, p.text);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
