import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

class FakeUser extends Mock implements User {
  FakeUser(String uid) {
    when(() => this.uid).thenReturn(uid);
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

ViceActivity fakeActivity(String viceID, int quantity, DateTime at) =>
    ViceActivity(
      id: '$viceID-$quantity-${at.toIso8601String()}',
      viceID: viceID,
      quantity: quantity,
      ownerID: ownerID,
      createdAt: Timestamp.fromDate(at),
    );
