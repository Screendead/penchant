import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';
import 'package:tracker/widgets/what_was_going_on_sheet.dart';

class _FakeReader implements NoteReader {
  final StreamController<ReadTag> tags = StreamController<ReadTag>();
  String? asked;

  @override
  Stream<ReadTag> read(String note) {
    asked = note;
    return tags.stream;
  }
}

const String _note = 'Out of the review, went to the pub with Sam';

void main() {
  late WhatWasGoingOnPick? done;
  late int undone;

  Future<void> pump(
    WidgetTester tester, {
    NoteReader? reader,
    bool still = false,
    List<String> initial = const <String>[],
  }) async {
    done = null;
    undone = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[noteReaderProvider.overrideWithValue(reader)],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: still,
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: WhatWasGoingOnSheet(
                  viceName: 'Wine',
                  initial: initial,
                  onDone: (WhatWasGoingOnPick p) => done = p,
                  onUndoLog: () => undone++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(WhatWasGoingOnSheet.nextKey));
    await tester.pumpAndSettle();
  }

  Finder chip(String path) =>
      find.widgetWithText(FilterChip, triggerDisplay(path));

  bool chipSelected(WidgetTester tester, String path) =>
      tester.widget<FilterChip>(chip(path)).selected;

  testWidgets('only Next and Back move between the panels', (tester) async {
    await pump(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.byKey(NoteField.fieldKey), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.byKey(NoteField.fieldKey), findsOneWidget);

    await next(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Areas of life'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);

    await next(tester);
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.byKey(UrgeField.keyFor(1)), findsOneWidget);
    expect(find.byKey(WhatWasGoingOnSheet.nextKey), findsNothing);

    await tester.tap(find.byKey(WhatWasGoingOnSheet.backKey));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(done, isNull);
  });

  for (int panel = 0; panel < 3; panel++) {
    testWidgets('Done on panel ${panel + 1} saves what is there', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byKey(NoteField.fieldKey), '  $_note ');
      for (int i = 0; i < panel; i++) {
        await next(tester);
      }
      if (panel == 2) {
        await tester.tap(find.byKey(UrgeField.keyFor(4)));
        await tester.pump();
      }
      await tester.tap(find.byKey(WhatWasGoingOnSheet.doneKey));
      await tester.pumpAndSettle();

      expect(done?.note, _note);
      expect(done?.triggers, isEmpty);
      expect(done?.urge, panel == 2 ? 4 : null);
    });
  }

  testWidgets('every panel offers Undo log', (tester) async {
    await pump(tester);
    for (int i = 0; i < 3; i++) {
      expect(find.text(undoLogLabel), findsOneWidget);
      if (i < 2) await next(tester);
    }
    await tester.tap(find.text(undoLogLabel));
    expect(undone, 1);
  });

  testWidgets('read tags arrive selected and can be dropped', (tester) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader);
    expect(find.text(WhatWasGoingOnSheet.readsHint), findsOneWidget);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    expect(reader.asked, _note);
    expect(find.text(WhatWasGoingOnSheet.readingLine), findsOneWidget);

    reader.tags
      ..add((path: 'work/meeting', quote: 'review'))
      ..add((path: 'place/bar', quote: 'the pub'));
    await reader.tags.close();
    await settle(tester);

    expect(find.text(WhatWasGoingOnSheet.tagsTitle), findsOneWidget);
    expect(find.text(WhatWasGoingOnSheet.readLine), findsOneWidget);
    expect(chipSelected(tester, 'work/meeting'), isTrue);
    expect(chipSelected(tester, 'place/bar'), isTrue);
    expect(
      find.text('Work or study'),
      findsOneWidget,
      reason: 'hand-picking stays',
    );

    await tester.tap(chip('work/meeting'));
    await tester.pumpAndSettle();
    expect(chipSelected(tester, 'work/meeting'), isFalse);

    // Back and Next again with the note unchanged keeps the drop.
    await tester.tap(find.byKey(WhatWasGoingOnSheet.backKey));
    await tester.pumpAndSettle();
    await next(tester);
    expect(chipSelected(tester, 'work/meeting'), isFalse);

    await tester.tap(find.byKey(WhatWasGoingOnSheet.doneKey));
    await tester.pumpAndSettle();
    expect(done?.triggers, <String>['place/bar']);
  });

  testWidgets('a read tag flies from the note to its chip', (tester) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    reader.tags.add((path: 'place/bar', quote: 'the pub'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(WhatWasGoingOnSheet.flyingKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(WhatWasGoingOnSheet.flyingKey), findsNothing);
    expect(chipSelected(tester, 'place/bar'), isTrue);
    await reader.tags.close();
  });

  testWidgets('Done mid-read saves only the tags already shown', (
    tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    reader.tags
      ..add((path: 'work/meeting', quote: 'review'))
      ..add((path: 'place/bar', quote: 'the pub'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(WhatWasGoingOnSheet.doneKey));
    await tester.pumpAndSettle();
    expect(done?.triggers, <String>['work/meeting']);
  });

  testWidgets('with reduced motion the tags just appear', (tester) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader, still: true);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    reader.tags.add((path: 'place/bar', quote: 'the pub'));
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(WhatWasGoingOnSheet.flyingKey), findsNothing);
    expect(chipSelected(tester, 'place/bar'), isTrue);
    expect(
      tester
          .widget<Visibility>(
            find
                .ancestor(
                  of: chip('place/bar'),
                  matching: find.byType(Visibility),
                )
                .first,
          )
          .visible,
      isTrue,
    );
    await reader.tags.close();
  });

  testWidgets('a quote not in the note or a path not in the tree is ignored', (
    tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    reader.tags
      ..add((path: 'work/deadline', quote: 'deadline on Friday'))
      ..add((path: 'work/nowhere', quote: 'review'))
      ..add((path: 'place/bar', quote: 'the pub'));
    await reader.tags.close();
    await settle(tester);

    expect(chip('work/deadline'), findsNothing);
    expect(find.byType(FilterChip), findsOneWidget);
    await tester.tap(find.byKey(WhatWasGoingOnSheet.doneKey));
    await tester.pumpAndSettle();
    expect(done?.triggers, <String>['place/bar']);
  });

  testWidgets('a reader error falls back to picking by hand', (tester) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    reader.tags.addError(StateError('offline'));
    await settle(tester);

    expect(find.text(WhatWasGoingOnSheet.failedLine), findsOneWidget);
    expect(find.text(WhatWasGoingOnSheet.tagsTitle), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Areas of life'), findsOneWidget);

    await tester.ensureVisible(find.text('Work or study'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work or study'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WhatWasGoingOnSheet.doneKey));
    await tester.pumpAndSettle();
    expect(done?.triggers, <String>['work']);
  });

  testWidgets('a reader that never answers gives up after 10 seconds', (
    tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await pump(tester, reader: reader);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    expect(find.text(WhatWasGoingOnSheet.readingLine), findsOneWidget);
    await tester.pump(WhatWasGoingOnSheet.readTimeout);
    await tester.pump();
    expect(find.text(WhatWasGoingOnSheet.failedLine), findsOneWidget);
    expect(find.text('Areas of life'), findsOneWidget);
  });

  testWidgets('without a reader the tags panel is the hand picker', (
    tester,
  ) async {
    await pump(tester, initial: const <String>['social']);
    expect(find.text(WhatWasGoingOnSheet.readsHint), findsNothing);
    await tester.enterText(find.byKey(NoteField.fieldKey), _note);
    await next(tester);
    expect(find.text(WhatWasGoingOnSheet.handTitle), findsOneWidget);
    expect(find.text(WhatWasGoingOnSheet.tagsTitle), findsNothing);
    expect(find.text(WhatWasGoingOnSheet.failedLine), findsNothing);
    expect(find.byType(InputChip), findsOneWidget);
    await tester.tap(find.byKey(WhatWasGoingOnSheet.doneKey));
    await tester.pumpAndSettle();
    expect(done?.triggers, <String>['social']);
  });
}
