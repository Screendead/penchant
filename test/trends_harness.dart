import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/trends/trends_sheet.dart';

import 'fakes.dart';

// Today with [vices] and [days]' entries, none by default; the Trends sheet reads each
// habit's range from [graph].
List<Override> trendsOverrides(
  List<Vice> vices,
  AsyncValue<List<ViceActivity>> Function(ViceActivityGraphQuery query) graph, {
  List<ViceActivity> Function(DateTime day)? days,
}) => <Override>[
  ...habitOverrides(vices),
  viceActivityDayProvider.overrideWith(
    (ref, DateTime day) => AsyncData(days?.call(day) ?? <ViceActivity>[]),
  ),
  viceActivityGraphProvider.overrideWith(
    (ref, ViceActivityGraphQuery query) => graph(query),
  ),
];

// [activities] within the queried range, as the graph query returns them.
AsyncValue<List<ViceActivity>> Function(ViceActivityGraphQuery) inRange(
  List<ViceActivity> activities,
) =>
    (ViceActivityGraphQuery query) => AsyncData(<ViceActivity>[
      for (final ViceActivity a in activities)
        if (a.viceID == query.viceID &&
            !a.createdAt.toDate().isBefore(query.start) &&
            a.createdAt.toDate().isBefore(query.end))
          a,
    ]);

Finder inTrends(Finder finder) =>
    find.descendant(of: find.byType(TrendsSheet), matching: finder);

// Opens the sheet from its peek, the way a tap on it does.
Future<void> openTrends(WidgetTester tester) async {
  await tester.tap(inTrends(find.text(TrendsSheet.title)));
  await tester.pumpAndSettle();
}
