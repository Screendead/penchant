import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
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

  // Only the triggers are sealed, so the quantity of a locked entry is real.
  testWidgets("a locked entry's delete is unavailable, its quantity is not", (
    tester,
  ) async {
    final ViceActivity locked = ViceActivity(
      id: activity.id,
      viceID: coffee.id,
      quantity: 2,
      ownerID: ownerID,
      createdAt: activity.createdAt,
      locked: true,
    );
    await pumpEditor(tester, AsyncData(locked));

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Quantity'),
              matching: find.byType(EditableText),
            ),
          )
          .readOnly,
      isFalse,
    );
  });

  testWidgets('reads a denied or deleted activity as not found at once', (
    tester,
  ) async {
    int listens = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          viceListProvider.overrideWithValue(AsyncData([coffee])),
          viceActivityForUserProvider.overrideWith((ref, key) {
            listens++;
            return Stream<ViceActivity?>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            );
          }),
        ],
        child: MaterialApp(
          home: ViceActivityEditorPage(
            viceID: coffee.id,
            activityID: activity.id,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Activity not found'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(listens, 1);
  });

  testWidgets("refuses an activity that belongs to another vice than the "
      "route's", (tester) async {
    await pumpEditor(tester, AsyncData(activity), routeViceID: 'tea');

    expect(find.text('Activity not found'), findsOneWidget);
  });
}
