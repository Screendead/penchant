import 'dart:ui';

import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';

import 'fake_writes.dart';

// Records every account call instead of making it. [respond] decides how each
// one completes; by default it succeeds at once.
class FakeAccount implements Account {
  final List<Write> calls = <Write>[];
  Future<void> Function(Write call)? respond;
  AccountData data = const AccountData(
    vices: <StoredDocument>[],
    activities: <StoredDocument>[],
  );

  Future<void> _call(String op, [Map<String, Object?> fields = const {}]) {
    final Write call = Write(op, '', fields);
    calls.add(call);
    return respond?.call(call) ?? Future<void>.value();
  }

  // Counted apart from [calls]: Account Settings reloads on every open.
  int reloads = 0;

  List<String> get ops => <String>[for (final Write call in calls) call.op];

  @override
  Future<void> signIn({required String email, required String password}) =>
      _call('signIn', <String, Object?>{'email': email, 'password': password});

  @override
  Future<void> register({required String email, required String password}) =>
      _call('register', <String, Object?>{
        'email': email,
        'password': password,
      });

  @override
  bool isGuest = false;

  @override
  Future<void> startAsGuest() => _call('startAsGuest');

  @override
  Future<void> linkEmail({required String email, required String password}) =>
      _call('linkEmail', <String, Object?>{
        'email': email,
        'password': password,
      });

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _call('sendPasswordResetEmail', <String, Object?>{'email': email});

  @override
  Future<void> sendEmailVerification() => _call('sendEmailVerification');

  @override
  Future<void> reauthenticate(String password) =>
      _call('reauthenticate', <String, Object?>{'password': password});

  @override
  Future<void> reloadUser() async {
    reloads++;
  }

  @override
  Future<void> updateDisplayName(String? displayName) =>
      _call('updateDisplayName', <String, Object?>{'displayName': displayName});

  @override
  Future<void> updatePhotoURL(String? photoURL) =>
      _call('updatePhotoURL', <String, Object?>{'photoURL': photoURL});

  @override
  Future<void> changeEmail(String email, {required String password}) => _call(
    'changeEmail',
    <String, Object?>{'email': email, 'password': password},
  );

  @override
  Future<void> signOut({bool discardUnsynced = false}) =>
      _call('signOut', <String, Object?>{'discardUnsynced': discardUnsynced});

  @override
  Future<AccountData> fetchData() async {
    await _call('fetchData');
    return data;
  }

  @override
  Future<void> deleteAccount({String? password}) =>
      _call('deleteAccount', <String, Object?>{'password': password});
}

class FakeExportShare implements ExportShare {
  final List<List<ExportFile>> shared = <List<ExportFile>>[];

  @override
  Future<void> share(List<ExportFile> files, {Rect? origin}) async {
    shared.add(files);
  }
}
