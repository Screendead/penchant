import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/password_prompt.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/photos_provider.dart';
import 'package:tracker/providers/places_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/widgets/amount_fields.dart';
import 'package:tracker/widgets/auth_parts.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/place_sheet.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

import 'fake_account.dart';
import 'fake_places.dart';
import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';

// Audits every text field against the iOS keyboard: the focused field and
// the surface's primary action must clear it, with no overflow.

class _Screen {
  const _Screen(
    this.name,
    this.size, {
    this.top = 0,
    this.bottom = 0,
    this.side = 0,
    required this.keyboard,
    this.landscape = false,
  });

  final String name;
  final Size size;
  final double top;
  final double bottom;
  final double side;
  final double keyboard;
  final bool landscape;

  double get keyboardTop => size.height - keyboard;
}

const List<_Screen> _screens = <_Screen>[
  _Screen('402x874', Size(402, 874), top: 62, bottom: 34, keyboard: 336),
  _Screen('375x667', Size(375, 667), top: 20, keyboard: 260),
  _Screen(
    'landscape 874x402',
    Size(874, 402),
    side: 62,
    bottom: 21,
    keyboard: 210,
    landscape: true,
  ),
];

const double _dpr = 3;

void _setView(WidgetTester tester, _Screen s) {
  final FakeViewPadding padding = FakeViewPadding(
    top: s.top * _dpr,
    bottom: s.bottom * _dpr,
    left: s.side * _dpr,
    right: s.side * _dpr,
  );
  tester.view
    ..devicePixelRatio = _dpr
    ..physicalSize = s.size * _dpr
    ..padding = padding
    ..viewPadding = padding
    ..viewInsets = FakeViewPadding.zero;
}

void _raiseKeyboard(WidgetTester tester, _Screen s) {
  tester.view
    ..padding = FakeViewPadding(
      top: s.top * _dpr,
      left: s.side * _dpr,
      right: s.side * _dpr,
    )
    ..viewInsets = FakeViewPadding(bottom: s.keyboard * _dpr);
}

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
  } on FlutterError {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

// As a tap does: focus with a caret, which EditableText needs before it
// scrolls itself clear of a rising keyboard.
Future<void> _focus(WidgetTester tester, Finder editable) async {
  await tester.showKeyboard(editable);
  final EditableTextState state = tester.state<EditableTextState>(editable);
  state.userUpdateTextEditingValue(
    state.textEditingValue.copyWith(
      selection: TextSelection.collapsed(
        offset: state.textEditingValue.text.length,
      ),
    ),
    SelectionChangedCause.tap,
  );
  await tester.pump();
}

// Builds a lazily built child by scrolling each vertical list to it.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (final Element e in find.byType(Scrollable).evaluate().toList()) {
    if (target.evaluate().isNotEmpty) return;
    final Scrollable sc = e.widget as Scrollable;
    if (axisDirectionToAxis(sc.axisDirection) != Axis.vertical) continue;
    try {
      await tester.scrollUntilVisible(
        target,
        100,
        scrollable: find.byWidget(sc),
        maxScrolls: 40,
      );
    } on Object {
      // Not in this scrollable.
    }
  }
}

String _fmt(double v) => v.toStringAsFixed(1);

class _Field {
  const _Field(this.name, this.reach);

  final String name;
  // Reveals the field on a freshly opened surface and returns a finder for it.
  final Future<Finder> Function(WidgetTester tester) reach;
}

Finder _editable(Finder field) => find
    .descendant(of: field, matching: find.byType(EditableText), matchRoot: true)
    .first;

Future<Finder> Function(WidgetTester) _plain(Finder field) =>
    (WidgetTester _) async => field;

Future<Finder> Function(WidgetTester) _after(Finder tapFirst, Finder field) =>
    (WidgetTester tester) async {
      await tester.ensureVisible(tapFirst.first);
      await _settle(tester);
      await tester.tap(tapFirst.first);
      await _settle(tester);
      return field;
    };

/// Opens [surface] afresh for each field at each screen size and checks it.
/// Returns one line per failure.
Future<List<String>> _audit(
  WidgetTester tester, {
  required String surface,
  required Future<void> Function(WidgetTester tester) open,
  required List<_Field> fields,
  required Finder action,
  List<_Screen> screens = _screens,
}) async {
  addTearDown(tester.view.reset);
  final List<String> failures = <String>[];
  for (final _Screen s in screens) {
    for (final _Field f in fields) {
      final String where = '$surface / ${f.name} / ${s.name}';
      _setView(tester, s);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await _settle(tester);
      Object? error = tester.takeException();
      if (error != null) {
        failures.add('$where: exception before the keyboard: $error');
      }

      final Finder field;
      try {
        field = await f.reach(tester);
      } on Object catch (e) {
        failures.add('$where: could not reach the field: $e');
        tester.takeException();
        continue;
      }
      await _scrollTo(tester, field);
      if (field.evaluate().isEmpty) {
        failures.add('$where: field not found');
        continue;
      }
      final Finder editable = _editable(field);
      await tester.ensureVisible(editable);
      await _settle(tester);
      await _focus(tester, editable);
      _raiseKeyboard(tester, s);
      await _settle(tester);

      final Rect rect = tester.getRect(editable);
      if (rect.bottom > s.keyboardTop + 0.01) {
        failures.add(
          '$where: field bottom ${_fmt(rect.bottom)} > keyboard top '
          '${_fmt(s.keyboardTop)}',
        );
      }
      if (rect.top < s.top - 0.01) {
        failures.add(
          '$where: field top ${_fmt(rect.top)} < top padding ${_fmt(s.top)}',
        );
      }

      error = tester.takeException();
      if (!s.landscape) {
        if (error != null) {
          failures.add('$where: exception with the keyboard up: $error');
        }
        await _scrollTo(tester, action);
        if (action.evaluate().isEmpty) {
          failures.add('$where: primary action not found');
        } else {
          await tester.ensureVisible(action.first);
          await _settle(tester);
          final Rect a = tester.getRect(action.first);
          if (a.bottom > s.keyboardTop + 0.01) {
            failures.add(
              '$where: action bottom ${_fmt(a.bottom)} > keyboard top '
              '${_fmt(s.keyboardTop)}',
            );
          }
          error = tester.takeException();
          if (error != null) {
            failures.add('$where: exception revealing the action: $error');
          }
        }
      }

      tester.testTextInput.hide();
      tester.view.resetViewInsets();
      await tester.pump();
      tester.takeException();
    }
  }
  return failures;
}

void _report(List<String> failures) {
  if (failures.isNotEmpty) {
    fail('${failures.length} keyboard failures:\n${failures.join('\n')}');
  }
}

final DateTime _now = DateTime(2026, 11, 5, 18, 30);

final Vice _coffee = Vice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  archived: false,
);

final ViceActivity _entry = fakeActivity('coffee', 3, _now);

Finder get _quantity =>
    find.widgetWithText(TextFormField, AmountFields.quantityLabel);

final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

List<Override> _entryOverrides() => <Override>[
  ...habitOverrides(<Vice>[_coffee]),
  trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
  memoryJournal(),
  userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
  viceActivityProvider.overrideWith((ref, String id) => AsyncData(_entry)),
  viceActivityDayProvider.overrideWith(
    (ref, DateTime day) => const AsyncData(<ViceActivity>[]),
  ),
  viceActivityHistoryProvider.overrideWith(
    (ref, query) => const AsyncData(<ViceActivity>[]),
  ),
];

// A root with a navigator to open routes on, keeping the user loaded as the
// app's root does.
Widget _host(List<Override> overrides, {Widget? home}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    navigatorKey: _navigator,
    theme: appTheme(Brightness.light),
    home:
        home ??
        Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            ref.watch(userProvider);
            return const Scaffold();
          },
        ),
  ),
);

Future<void> _openRoute(
  WidgetTester tester,
  List<Override> overrides,
  void Function(BuildContext context) show,
) async {
  await tester.pumpWidget(_host(overrides));
  await tester.pump();
  show(_navigator.currentContext!);
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('amount sheet', (WidgetTester tester) async {
    await withClock(Clock.fixed(_now), () async {
      _report(
        await _audit(
          tester,
          surface: 'amount sheet',
          open: (WidgetTester t) => _openRoute(
            t,
            _entryOverrides(),
            (BuildContext c) =>
                RecordNewActivityDialog.show(c, initialViceID: _coffee.id),
          ),
          fields: <_Field>[
            _Field('quantity', _plain(_quantity)),
            _Field('note', _plain(find.byKey(NoteField.fieldKey))),
          ],
          action: find.byKey(RecordNewActivityDialog.submitKey),
        ),
      );
    });
  });

  testWidgets('entry editor', (WidgetTester tester) async {
    await withClock(Clock.fixed(_now), () async {
      _report(
        await _audit(
          tester,
          surface: 'entry editor',
          open: (WidgetTester t) => _openRoute(
            t,
            _entryOverrides(),
            (BuildContext c) => Navigator.of(c).push(
              ViceActivityEditorPage.route(
                const RouteSettings(),
                ViceActivityEditorPage(
                  viceID: _coffee.id,
                  activityID: _entry.id,
                ),
              ),
            ),
          ),
          fields: <_Field>[
            _Field('quantity', _plain(_quantity)),
            _Field('note', _plain(find.byKey(NoteField.fieldKey))),
          ],
          action: find.byKey(ViceActivityEditorPage.saveKey),
        ),
      );
    });
  });

  testWidgets('trigger picker', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'trigger picker',
        open: (WidgetTester t) => _openRoute(
          t,
          _entryOverrides(),
          (BuildContext c) => showTriggerPicker(
            c,
            viceID: _coffee.id,
            viceName: _coffee.name,
            initial: const <String>[],
            answers: (urge: null, note: null),
          ),
        ),
        fields: <_Field>[
          _Field(
            'level-one free text',
            _after(
              find.text('Your own words'),
              find.widgetWithText(TextField, 'In your own words'),
            ),
          ),
          _Field('note', _plain(find.byKey(NoteField.fieldKey))),
          _Field(
            'level-two free text',
            _after(
              find.text(triggerTree.first.label),
              find.widgetWithText(
                TextField,
                'Something else, in your own words',
              ),
            ),
          ),
        ],
        action: find.text('Done'),
      ),
    );
  });

  testWidgets('place sheet', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'place sheet',
        open: (WidgetTester t) => _openRoute(
          t,
          <Override>[
            placesSourceProvider.overrideWithValue(
              FakePlaces(PlacesAccess.always),
            ),
            photosSourceProvider.overrideWithValue(
              FakePhotos(PhotosAccess.notDetermined),
            ),
          ],
          (BuildContext c) => showPlaceSheet(
            c,
            place: const Place(
              id: 3,
              latitude: 51.5,
              longitude: -0.1,
              visits: 4,
            ),
            stays: <PlaceStay>[
              PlaceStay(3, DateTime(2026, 3, 2, 9), DateTime(2026, 3, 2, 17)),
            ],
          ),
        ),
        fields: <_Field>[_Field('name', _plain(find.byType(TextField)))],
        action: find.widgetWithText(FilledButton, 'Save'),
      ),
    );
  });

  testWidgets('habit form', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'habit form',
        open: (WidgetTester t) async {
          await t.pumpWidget(
            _host(<Override>[
              userProvider.overrideWith((ref) => Stream.value(FakeUser('u'))),
            ], home: const ViceForm()),
          );
          await t.pump();
        },
        fields: <_Field>[
          _Field(
            'name',
            _plain(find.widgetWithText(TextFormField, 'Habit Name')),
          ),
          _Field('unit label', _plain(find.byKey(ViceForm.unitLabelKey))),
          _Field('singular', (WidgetTester t) async {
            await t.ensureVisible(find.byKey(ViceForm.unitLabelKey));
            await t.enterText(find.byKey(ViceForm.unitLabelKey), 'glasses');
            await _settle(t);
            return find.byKey(ViceForm.unitSingularKey);
          }),
          _Field('price', _plain(find.byKey(ViceForm.costKey))),
          _Field(
            'line amount',
            _after(find.text('A day'), find.byKey(ViceForm.lineAmountKey)),
          ),
        ],
        action: find.widgetWithText(TextButton, 'Save'),
      ),
    );
  });

  Future<void> openAuth(WidgetTester t) async {
    await t.pumpWidget(
      _host(<Override>[
        accountProvider.overrideWithValue(FakeAccount()),
      ], home: const Authenticate()),
    );
  }

  Finder authField(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('sign in', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'sign in',
        open: openAuth,
        fields: <_Field>[
          _Field('email', _plain(authField('Email'))),
          _Field('password', _plain(authField('Password'))),
        ],
        action: find.byType(AuthPrimaryButton),
      ),
    );
  });

  testWidgets('register', (WidgetTester tester) async {
    Future<Finder> Function(WidgetTester) inRegister(String label) =>
        _after(find.byKey(Authenticate.registerTab), authField(label));
    _report(
      await _audit(
        tester,
        surface: 'register',
        open: openAuth,
        fields: <_Field>[
          _Field('email', inRegister('Email')),
          _Field('password', inRegister('Password')),
          _Field('confirm password', inRegister('Confirm password')),
        ],
        action: find.byType(AuthPrimaryButton),
      ),
    );
  });

  testWidgets('reset password dialog', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'reset password dialog',
        open: openAuth,
        fields: <_Field>[
          _Field(
            'email',
            _after(
              find.text(AccountCopy.forgotPassword),
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextFormField),
              ),
            ),
          ),
        ],
        action: find.text(AccountCopy.resetSend),
      ),
    );
  });

  Future<void> openAccount(WidgetTester t, {bool guest = false}) async {
    final User user = FakeUser(
      ownerID,
      email: guest ? null : 'sam@example.com',
      isAnonymous: guest,
    );
    await t.pumpWidget(
      _host(<Override>[
        accountProvider.overrideWithValue(FakeAccount()..isGuest = guest),
        exportShareProvider.overrideWithValue(FakeExportShare()),
        userProvider.overrideWith((ref) => Stream.value(user)),
        userProfileProvider.overrideWith((ref) => Stream.value(user)),
      ], home: const AccountSettings()),
    );
    await t.pump();
  }

  testWidgets('account settings', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'account settings',
        open: openAccount,
        fields: <_Field>[
          for (final String label in <String>[
            'Display Name',
            'Email',
            'Photo URL',
          ])
            _Field(label, _plain(authField(label))),
        ],
        action: find.text('Update Profile'),
      ),
    );
  });

  testWidgets('account settings, guest', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'account settings (guest)',
        open: (WidgetTester t) => openAccount(t, guest: true),
        fields: <_Field>[
          for (final String label in <String>[
            'Email',
            'Password',
            'Confirm password',
          ])
            _Field(label, _plain(authField(label))),
        ],
        action: find.text(AccountCopy.linkAction),
      ),
    );
  });

  testWidgets('password prompt', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'password prompt',
        open: (WidgetTester t) => _openRoute(
          t,
          <Override>[],
          (BuildContext c) =>
              promptForPassword(c, message: 'Confirm it is you', action: 'Go'),
        ),
        fields: <_Field>[
          _Field(
            'password',
            _plain(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextField),
              ),
            ),
          ),
        ],
        action: find.widgetWithText(TextButton, 'Go'),
      ),
    );
  });

  final String formatted = RecoveryKey.format(RecoveryKey.generate(Random(11)));

  Widget recoveryApp(List<Override> overrides, Widget home) => ProviderScope(
    overrides: <Override>[
      e2eeEnabledProvider.overrideWithValue(true),
      userProvider.overrideWith((ref) => Stream<User?>.value(FakeUser('u'))),
      ...overrides,
    ],
    child: MaterialApp(
      theme: appTheme(Brightness.light),
      routes: <String, WidgetBuilder>{
        RecoveryKeyPage.route: (_) => const RecoveryKeyPage(),
      },
      builder: (BuildContext context, Widget? child) =>
          RecoveryKeyGate(child: child!),
      home: home,
    ),
  );

  testWidgets('recovery key confirm step', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'recovery key confirm',
        open: (WidgetTester t) async {
          await t.pumpWidget(
            recoveryApp(
              <Override>[
                recoveryKeyStatusProvider.overrideWithValue(
                  RecoveryKeyStatus(
                    formatted: formatted,
                    keyCreatedAt: DateTime(2026, 11, 1),
                  ),
                ),
                recoveryKeyActionsProvider.overrideWithValue(_NoActions()),
              ],
              Builder(
                builder: (BuildContext context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(RecoveryKeyPage.route),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('open'));
          await _settle(t);
        },
        fields: <_Field>[
          _Field(
            'confirm',
            _after(
              find.text(RecoveryKeyCopy.savedIt),
              find.byKey(RecoveryKeyPage.confirmField),
            ),
          ),
        ],
        action: find.text(RecoveryKeyCopy.confirm),
      ),
    );
  });

  testWidgets('recovery key entry', (WidgetTester tester) async {
    _report(
      await _audit(
        tester,
        surface: 'recovery key entry',
        open: (WidgetTester t) async {
          await t.pumpWidget(
            recoveryApp(<Override>[
              journalNeedsRecoveryKeyProvider.overrideWithValue(true),
              recoveryKeyActionsProvider.overrideWithValue(_NoActions()),
              accountProvider.overrideWithValue(FakeAccount()),
            ], const Text('journal')),
          );
          await t.pump();
        },
        fields: <_Field>[
          _Field('key', _plain(find.byKey(RecoveryKeyEntryPage.field))),
        ],
        action: find.text(RecoveryKeyCopy.unlock),
      ),
    );
  });

  testWidgets("Today's dial stays put under the amount sheet's keyboard", (
    WidgetTester tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final List<String> moved = <String>[];
      addTearDown(tester.view.reset);
      for (final _Screen s in _screens) {
        _setView(tester, s);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              ..._entryOverrides().skip(3).take(4),
              viceActivityHistoryProvider.overrideWith(
                (ref, query) => const AsyncData(<ViceActivity>[]),
              ),
              offlineProvider.overrideWith((ref) => Stream.value(false)),
              pendingWritesWaiterProvider.overrideWithValue(() async {}),
              ...trendsOverrides(<Vice>[
                _coffee,
              ], (_) => const AsyncData<List<ViceActivity>>(<ViceActivity>[])),
            ],
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              home: const Homepage(),
            ),
          ),
        );
        await _settle(tester);
        RecordNewActivityDialog.show(
          tester.element(find.byType(DayDial)),
          initialViceID: _coffee.id,
        );
        await _settle(tester);
        final Rect before = tester.getRect(
          find.byType(DayDial, skipOffstage: false),
        );
        await _focus(tester, _editable(_quantity));
        _raiseKeyboard(tester, s);
        await _settle(tester);
        final Rect after = tester.getRect(
          find.byType(DayDial, skipOffstage: false),
        );
        tester.takeException();
        if (before != after) {
          moved.add('${s.name}: dial $before -> $after');
        }
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await tester.pump();
      }
      _report(moved);
    });
  });
}

class _NoActions implements RecoveryKeyActions {
  @override
  Future<void> markSaved() async {}

  @override
  Future<void> dismissCard() async {}

  @override
  Future<UnlockOutcome> unlock(Uint8List recoveryKey) async =>
      const UnlockOpened();

  @override
  Future<void> startNewJournal() async {}
}
