import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';

import 'fakes.dart';

void main() {
  final Vice coffee = fakeVice('coffee');
  final ViceActivity activity = fakeActivity(
    coffee.id,
    2,
    DateTime(2026, 11, 2, 9, 30),
  );

  Future<void> pumpEditor(
    WidgetTester tester,
    AsyncValue<ViceActivity?> value, {
    String? routeViceID,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          viceListProvider.overrideWithValue(
            AsyncData([coffee, fakeVice('tea')]),
          ),
          viceActivityProvider.overrideWith((ref, String id) => value),
        ],
        child: MaterialApp(
          home: ViceActivityEditorPage(
            viceID: routeViceID ?? coffee.id,
            activityID: activity.id,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('edits the activity its route names', (tester) async {
    await pumpEditor(tester, AsyncData(activity));

    expect(find.text('Edit coffee activity'), findsOneWidget);
  });

  testWidgets('reads a denied or deleted activity as not found', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      AsyncError<ViceActivity?>(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        StackTrace.empty,
      ),
    );

    expect(find.text('Activity not found'), findsOneWidget);
  });

  testWidgets("refuses an activity that belongs to another vice than the "
      "route's", (tester) async {
    await pumpEditor(tester, AsyncData(activity), routeViceID: 'tea');

    expect(find.text('Activity not found'), findsOneWidget);
  });
}
