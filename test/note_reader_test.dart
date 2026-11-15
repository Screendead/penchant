import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/notes/note_reader_setting.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fakes.dart';

const String _note =
    'Boss tore into the roadmap, went to the pub with Sam and stayed late.';

Map<String, Object?> _tag(String path, String quote) => <String, Object?>{
  'path': path,
  'quote': quote,
};

void main() {
  group('CallableNoteReader', () {
    test(
      'sends the note and emits only tags the tree and note bear out',
      () async {
        final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
        final CallableNoteReader reader = CallableNoteReader((data) async {
          sent.add(data);
          return <String, Object?>{
            'reason': 'ok',
            'tags': <Object?>[
              _tag('work/hard-talk', 'Boss tore into the roadmap'),
              _tag('work/made-up', 'roadmap'),
              _tag('place/bar', 'went to the bar'),
              _tag('place/bar', 'the pub'),
              _tag('social/friends', 'with Sam'),
              _tag('social/friends', 'Sam'),
              _tag('feeling/low', ' '),
              'nonsense',
              _tag('work/long-day', 'stayed late'),
              _tag('social', 'Sam'),
            ],
          };
        });
        final List<ReadTag> tags = await reader.read(_note).toList();
        expect(sent, <Object?>[
          <String, Object?>{'note': _note},
        ]);
        expect(tags, <ReadTag>[
          (path: 'work/hard-talk', quote: 'Boss tore into the roadmap'),
          (path: 'place/bar', quote: 'the pub'),
          (path: 'social/friends', quote: 'with Sam'),
          (path: 'work/long-day', quote: 'stayed late'),
        ]);
      },
    );

    test('an empty or overlong note is never sent', () async {
      int calls = 0;
      final CallableNoteReader reader = CallableNoteReader((_) async {
        calls++;
        return null;
      });
      expect(await reader.read('  ').toList(), isEmpty);
      expect(await reader.read('x' * 501).toList(), isEmpty);
      expect(calls, 0);
    });

    test(
      'a reason other than ok, or a failed call, is a stream error',
      () async {
        final CallableNoteReader refused = CallableNoteReader(
          (_) async => <String, Object?>{
            'tags': <Object?>[],
            'reason': 'refusal',
          },
        );
        await expectLater(
          refused.read(_note),
          emitsError(
            isA<NoteReadFailed>().having((e) => e.reason, 'reason', 'refusal'),
          ),
        );
        final CallableNoteReader failing = CallableNoteReader(
          (_) async => throw StateError('offline'),
        );
        await expectLater(failing.read(_note), emitsError(isA<StateError>()));
        expect(CallableNoteReader.tagsIn('garbage', _note), isEmpty);
      },
    );

    test('no answer within 10 s is a timeout error', () {
      fakeAsync((FakeAsync async) {
        final CallableNoteReader reader = CallableNoteReader(
          (_) => Completer<Object?>().future,
        );
        Object? error;
        reader.read(_note).listen(null, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 9));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, isA<TimeoutException>());
      });
    });
  });

  group('noteReaderProvider', () {
    Future<NoteReader?> readerWith({
      required bool enabled,
      required User? user,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        NoteReaderEnabled.key: enabled,
      });
      final ProviderContainer container = ProviderContainer(
        overrides: [userProvider.overrideWith((ref) => Stream.value(user))],
      );
      addTearDown(container.dispose);
      container.listen(noteReaderProvider, (_, _) {});
      await pumpEventQueue();
      return container.read(noteReaderProvider);
    }

    test('is a reader only while switched on with someone signed in', () async {
      expect(
        await readerWith(enabled: true, user: FakeUser('a')),
        isA<CallableNoteReader>(),
      );
      expect(await readerWith(enabled: false, user: FakeUser('a')), isNull);
      expect(await readerWith(enabled: true, user: null), isNull);
    });

    test('is off by default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer container = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser('a'))),
        ],
      );
      addTearDown(container.dispose);
      container.listen(noteReaderProvider, (_, _) {});
      await pumpEventQueue();
      expect(container.read(noteReaderEnabledProvider), isFalse);
      expect(container.read(noteReaderProvider), isNull);
    });
  });

  group('NoteReaderSetting', () {
    Widget app() => ProviderScope(
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: NoteReaderSetting()),
      ),
    );

    Future<bool?> saved() async =>
        (await SharedPreferences.getInstance()).getBool(NoteReaderEnabled.key);

    testWidgets('turning on asks first, and Not now leaves it off', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(NoteReaderSetting.disclosure), findsOneWidget);
      expect(NoteReaderSetting.disclosure, contains('Anthropic'));
      expect(NoteReaderSetting.disclosure, contains('training'));
      expect(NoteReaderSetting.disclosure, contains('encrypted'));
      await tester.tap(find.text(NoteReaderSetting.notNow));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(await saved(), isNull);

      await tester.tap(find.text(NoteReaderSetting.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NoteReaderSetting.turnOn));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(await saved(), isTrue);
    });

    testWidgets('turning off needs no asking', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        NoteReaderEnabled.key: true,
      });
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(NoteReaderSetting.disclosure), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(await saved(), isFalse);
    });
  });
}
