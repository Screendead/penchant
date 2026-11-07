import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

class FakeUser extends Mock implements User {
  FakeUser(
    String uid, {
    String? email = 'someone@example.com',
    String? displayName,
    String? photoURL,
    bool emailVerified = false,
  }) {
    when(() => this.uid).thenReturn(uid);
    when(() => this.email).thenReturn(email);
    when(() => this.displayName).thenReturn(displayName);
    when(() => this.photoURL).thenReturn(photoURL);
    when(() => this.emailVerified).thenReturn(emailVerified);
  }
}

const String ownerID = 'owner';

Vice fakeVice(String id, {String? name}) => Vice(
  id: id,
  name: name ?? id,
  unit: Unit.values.first,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
);

ViceActivity fakeActivity(
  String viceID,
  int quantity,
  DateTime at, {
  List<String> triggers = const <String>[],
}) => ViceActivity(
  id: '$viceID-$quantity-${at.toIso8601String()}',
  viceID: viceID,
  quantity: quantity,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(at),
  triggers: triggers,
);

// Today colours each habit by its place among all of them, archived ones
// included, so it reads the full list as well as the unarchived one.
List<Override> habitOverrides(
  List<Vice> vices, {
  Map<String, double> storedTypicals = const <String, double>{},
}) => <Override>[
  storedTypicalsProvider.overrideWithValue(storedTypicals),
  viceListProvider.overrideWithValue(AsyncData<List<Vice>>(vices)),
  unarchivedViceListProvider.overrideWithValue(
    AsyncData<List<Vice>>(<Vice>[
      for (final Vice v in vices)
        if (!v.archived) v,
    ]),
  ),
];
