import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/widgets/urge_sheet.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

import 'fake_writes.dart';
import 'fakes.dart';

final Vice _wine = Vice(
  id: 'wine',
  name: 'Wine',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  archived: false,
);

Urge _urge(DateTime at, {int strength = 3, UrgeOutcome? outcome}) => Urge(
  id: 'u-${at.millisecondsSinceEpoch}',
  ownerID: ownerID,
  viceID: 'wine',
  createdAt: Timestamp.fromDate(at),
  content: UrgeContent(
    strength: strength,
    outcome: outcome,
    outcomeAt: outcome == null ? null : at.add(const Duration(minutes: 15)),
  ),
);

void main() {
  group('content', () {
    test('round-trips through the envelope map, outcome with its time', () {
      final DateTime at = DateTime(2026, 11, 15, 14, 20);
      final UrgeContent c = const UrgeContent(
        strength: 4,
        zone: 'Europe/London',
      ).answered(UrgeOutcome.passed, at);
      final UrgeContent back = UrgeContent.read(c.toMap());
      expect(back.strength, 4);
      expect(back.zone, 'Europe/London');
      expect(back.outcome, UrgeOutcome.passed);
      expect(back.outcomeAt, at);
      expect(c.toMap().keys, everyElement(isIn(urgeContentFields)));
    });

    test('reads a missing, mistyped or half outcome as none', () {
      expect(UrgeContent.read(const <String, Object?>{}).strength, isNull);
      expect(
        UrgeContent.read(const <String, Object?>{'strength': 9}).strength,
        isNull,
      );
      final UrgeContent half = UrgeContent.read(const <String, Object?>{
        'strength': 2,
        'outcome': 'passed',
      });
      expect(half.outcome, isNull);
      expect(half.toMap().containsKey('outcome'), isFalse);
      expect(
        UrgeContent.read(const <String, Object?>{
          'outcome': 'beaten',
          'outcomeAt': 1,
        }).outcome,
        isNull,
      );
    });

    test('a document that will not open is locked', () {
      final Urge u = Urge.fromJson(
        id: 'x',
        json: <String, dynamic>{'ownerID': ownerID, 'viceID': 'wine'},
      );
      expect(u.locked, isTrue);
      expect(u.content.strength, isNull);
    });
  });

  test('every list of owned and sealed collections names urges', () {
    expect(Account.ownedCollections, contains(urgesCollection));
    expect(contentFields[urgesCollection], urgeContentFields);
    expect(bornSealedCollections, contains(urgesCollection));
  });

  group('chart', () {
    final DateTime today = DateTime(2026, 11, 16);
    final UsageRange range = usageRange(today, 7, 1);

    test('places each urge at its time within its day, in no total', () {
      final List<Urge> urges = <Urge>[
        _urge(DateTime(2026, 11, 16, 12)),
        _urge(DateTime(2026, 11, 10, 6)),
        _urge(DateTime(2026, 11, 1, 12)),
      ];
      expect(urgeCounts(range, urges), <int>[1, 0, 0, 0, 0, 0, 1]);
      final List<double> xs = urgeChartPositions(range, urges);
      expect(xs, hasLength(2));
      expect(xs.first, closeTo(-0.25, 1e-9));
      expect(xs.last, closeTo(6, 1e-9));
    });

    test('names urges in the summary and readout without changing totals', () {
      final List<double> totals = <double>[1, 0, 2, 0, 0, 0, 1];
      final List<Urge> urges = <Urge>[
        _urge(DateTime(2026, 11, 16, 13)),
        _urge(DateTime(2026, 11, 16, 15)),
      ];
      final String plain = TrendsChart.summary(
        vice: _wine,
        range: range,
        totals: totals,
        smoothingWindow: 1,
      );
      final String marked = TrendsChart.summary(
        vice: _wine,
        range: range,
        totals: totals,
        smoothingWindow: 1,
        urges: urges,
      );
      expect(plain, isNot(contains('urge')));
      expect(marked, startsWith(plain.substring(0, plain.indexOf('.') + 1)));
      expect(marked, contains('4 drinks in all'));
      expect(marked, contains('2 urges noted, not counted in the totals'));
      expect(
        TrendsChart.readoutSpoken(
          vice: _wine,
          range: range,
          totals: totals,
          smoothed: totals,
          window: 1,
          index: 6,
          urgeCounts: urgeCounts(range, urges),
        ),
        'Today, 1 drink; 2 urges',
      );
    });
  });

  group('check-in', () {
    test('a payload names the urge alone, and each button its outcome', () {
      final String payload = urgePayload('abc');
      expect(payload, 'urge:abc');
      expect(
        nudgeTapFor('urge-passed', payload: payload),
        const NudgeTap(NudgeAction.urgePassed, urgeID: 'abc'),
      );
      expect(
        nudgeTapFor('urge-still-there', payload: payload)?.action,
        NudgeAction.urgeStillThere,
      );
      expect(
        nudgeTapFor('urge-had-one', payload: payload)?.action,
        NudgeAction.urgeHadOne,
      );
      expect(nudgeTapFor(null, payload: payload)?.action, NudgeAction.urge);
      expect(urgeOfPayload('heavy-day:2026-11-15'), isNull);
      expect(urgeOfPayload('urge:'), isNull);
    });

    test('its ids stay clear of the nudge and the experiment', () {
      expect(freeUrgeNoticeId(<int>[1, 2, 3, 1000]), urgeNoticeBase);
      expect(freeUrgeNoticeId(<int>[3000, 3001]), 3002);
      expect(urgeNoticeBase, greaterThanOrEqualTo(2000));
      expect(
        freeUrgeNoticeId(<int>[
          for (
            int i = urgeNoticeBase;
            i < urgeNoticeBase + urgeNoticeCount;
            i++
          )
            i,
        ]),
        isNull,
      );
    });

    test('its words name no habit and no strength', () {
      expect(NudgeCopy.urgeBody, 'Still there?');
    });
  });

  test('exports urges as their own CSV, oldest first', () {
    final AccountData data = AccountData(
      vices: <StoredDocument>[
        (id: 'wine', data: <String, dynamic>{'name': 'Wine'}),
      ],
      activities: const <StoredDocument>[],
      urges: <StoredDocument>[
        (
          id: 'b',
          data: <String, dynamic>{
            'viceID': 'wine',
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 15, 14)),
            'strength': 2,
            'outcome': 'hadOne',
            'outcomeAt': DateTime.utc(
              2026,
              11,
              15,
              14,
              15,
            ).millisecondsSinceEpoch,
          },
        ),
        (
          id: 'a',
          data: <String, dynamic>{
            'viceID': 'wine',
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14, 9)),
            'strength': 4,
          },
        ),
      ],
    );
    final List<String> lines = exportUrgesCsv(data).trim().split('\n');
    expect(lines.first.trim(), urgesCsvHeader.join(','));
    expect(lines[1], contains(',a,4,'));
    expect(lines[2], contains(',b,2,hadOne,2026-11-15T14:15:00.000Z'));
    expect(
      exportFiles(
        data,
        DateTime.utc(2026, 11, 16),
      ).map((ExportFile f) => f.name),
      contains('penchant-urges-2026-11-16.csv'),
    );
    expect(
      exportFiles(
        const AccountData(
          vices: <StoredDocument>[],
          activities: <StoredDocument>[],
        ),
        DateTime.utc(2026, 11, 16),
      ).map((ExportFile f) => f.name),
      isNot(contains('penchant-urges-2026-11-16.csv')),
    );
  });

  group('tile and sheet', () {
    Future<FakeTrackerWrites> pump(WidgetTester tester) async {
      final FakeTrackerWrites writes = FakeTrackerWrites();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...habitOverrides(<Vice>[_wine]),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            trackerWritesProvider.overrideWithValue(writes),
            memoryJournal(),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: Scaffold(
              // Today watches the user; nothing else here would.
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  ref.watch(userProvider);
                  return TallyRow(
                    vice: _wine,
                    mark: const HabitMark(0),
                    total: 0,
                    day: DateTime(2026, 11, 16),
                    onLog: (_) {},
                    actions: <TileAction>[
                      (
                        label: TallyRow.urgeAction,
                        onSelected: () => UrgeSheet.show(context, _wine),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return writes;
    }

    testWidgets('a long press offers Urge; the sheet notes its strength', (
      WidgetTester tester,
    ) async {
      final FakeTrackerWrites writes = await pump(tester);
      await tester.longPress(find.byType(TallyRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TallyRow.urgeAction));
      await tester.pumpAndSettle();
      expect(find.text(UrgeSheet.newStrengthLabel), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(UrgeSheet.doneKey)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(UrgeField.keyFor(4)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UrgeSheet.doneKey));
      await tester.pumpAndSettle();
      expect(writes.writes.single.op, 'recordUrge');
      expect(writes.writes.single.fields['strength'], 4);
      expect(writes.writes.single.fields['viceID'], 'wine');
      expect(find.textContaining('Urge noted for'), findsOneWidget);
      // Undo deletes it.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(writes.writes.last.op, 'deleteUrge');
    });

    testWidgets('a screen reader reaches Urge as a custom action', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pump(tester);
      final SemanticsNode node = tester.getSemantics(find.byType(TallyRow));
      final List<String?> labels = <String?>[
        for (final int id
            in node.getSemanticsData().customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(labels, contains(TallyRow.urgeAction));
      semantics.dispose();
    });
  });
}
