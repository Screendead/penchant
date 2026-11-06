import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/writes/queued_write_journal.dart';

typedef StoredDocument = ({String id, Map<String, dynamic> data});

@immutable
class AccountData {
  const AccountData({required this.vices, required this.activities});

  final List<StoredDocument> vices;
  final List<StoredDocument> activities;
}

// Thrown by signOut and deleteAccount when entries recorded on this device
// have not reached the server: clearing the cache would discard them, and a
// deletion could miss them.
class UnsyncedEntriesException implements Exception {
  const UnsyncedEntriesException();
}

// Thrown by deleteAccount when it fails after it began removing data: some
// documents may be gone while the account remains. Any other failure from it
// removed nothing.
class DeletionIncompleteException implements Exception {
  const DeletionIncompleteException(this.cause);

  final Object cause;
}

// Every Firebase Auth call the app makes, and the account-wide Firestore work
// that goes with them: export, deletion and clearing the on-device cache.
class Account {
  Account(this._auth, this._firestore, this._queuedWrites);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final QueuedWriteJournal _queuedWrites;

  // The quotas page sets no per-batch write count, only a 10 MiB request
  // limit; 500 deletes stay far below it.
  static const int pageSize = 500;

  static const Duration _syncWait = Duration(seconds: 5);

  static const List<String> _ownedCollections = <String>['activities', 'vices'];

  User _signedInUser() {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('No user is signed in.');
    }
    return user;
  }

  Future<void> signIn({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    final UserCredential credential = await _auth
        .createUserWithEmailAndPassword(email: email, password: password);
    try {
      await credential.user?.sendEmailVerification();
    } on FirebaseAuthException catch (e, stack) {
      // The account exists by now; Account Settings offers to resend.
      _report(e, stack, 'sending the verification email');
    }
  }

  // A guest's uid owns its data like any other, until it is linked to an
  // email and password or lost by signing out.
  Future<void> startAsGuest() => _auth.signInAnonymously();

  // Read live: the User a provider holds is a snapshot that linking leaves
  // anonymous.
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  // Linking keeps the uid, so the guest's entries stay theirs with nothing
  // copied.
  Future<void> linkEmail({
    required String email,
    required String password,
  }) async {
    final UserCredential credential = await _signedInUser().linkWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    try {
      await credential.user?.sendEmailVerification();
    } on FirebaseAuthException catch (e, stack) {
      _report(e, stack, 'sending the verification email');
    }
    // userChanges re-emits on a reload, so screens see the email and the
    // account as no longer anonymous.
    await reloadUser();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> sendEmailVerification() {
    return _signedInUser().sendEmailVerification();
  }

  Future<void> reauthenticate(String password) async {
    final User user = _signedInUser();
    final String? email = user.email;
    if (email == null) {
      throw StateError('The signed-in user has no email address.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  // Picks up what changed outside the app, such as a verified address. The
  // snapshot already held stays usable, so a failure is only reported.
  Future<void> reloadUser() async {
    try {
      await _auth.currentUser?.reload();
    } on FirebaseAuthException catch (e, stack) {
      _report(e, stack, 'reloading the signed-in user');
    }
  }

  // The iOS SDK leaves a nil name out of the request, and the plugin's reload
  // afterwards brings the old one back; an empty name clears it.
  Future<void> updateDisplayName(String? displayName) {
    return _signedInUser().updateDisplayName(displayName ?? '');
  }

  Future<void> updatePhotoURL(String? photoURL) {
    return _signedInUser().updatePhotoURL(photoURL);
  }

  // The address changes only once the user follows the link sent to it.
  Future<void> changeEmail(String email, {required String password}) async {
    await reauthenticate(password);
    await _signedInUser().verifyBeforeUpdateEmail(email);
  }

  Future<void> signOut({bool discardUnsynced = false}) async {
    if (!discardUnsynced) {
      try {
        await _firestore.waitForPendingWrites().timeout(_syncWait);
      } on TimeoutException {
        throw const UnsyncedEntriesException();
      }
    }
    await _auth.signOut();
    await _clearLocalCache();
  }

  Future<AccountData> fetchData() async {
    final String uid = _signedInUser().uid;
    return AccountData(
      vices: await _readOwned('vices', uid),
      activities: await _readOwned('activities', uid),
    );
  }

  // Data goes before the Auth user: Firebase never reissues a uid, so
  // documents left behind a deleted user could never be reached again.
  // A guest has no password to confirm with, so [password] is null for one.
  Future<void> deleteAccount({String? password}) async {
    if (password != null) {
      await reauthenticate(password);
    } else if (!_signedInUser().isAnonymous) {
      throw StateError('Deleting an account with an email needs its password.');
    }
    final User user = _signedInUser();
    // An entry still queued here could reach the server after the sweep below
    // and outlive its owner. Offline this refuses before anything is removed.
    try {
      await _firestore.waitForPendingWrites().timeout(_syncWait);
    } on TimeoutException {
      throw const UnsyncedEntriesException();
    }
    bool removing = false;
    try {
      for (final String collection in _ownedCollections) {
        await _deleteOwned(
          collection,
          user.uid,
          beforeCommit: () => removing = true,
        );
      }
      await _deleteUser(user);
    } catch (e, stack) {
      if (!removing) {
        rethrow;
      }
      Error.throwWithStackTrace(DeletionIncompleteException(e), stack);
    }
    await _clearLocalCache();
  }

  // A guest cannot re-authenticate, so a guest whose sign-in is too old to
  // delete is signed out instead: its data is gone and nothing can reach the
  // empty account again.
  Future<void> _deleteUser(User user) async {
    try {
      await user.delete();
    } on FirebaseAuthException catch (e, stack) {
      if (!user.isAnonymous || e.code != 'requires-recent-login') {
        rethrow;
      }
      _report(e, stack, 'deleting a guest whose sign-in is old');
      await _auth.signOut();
    }
  }

  // Equality on ownerID ordered by document id is served by the automatic
  // single-field index, so this needs no entry in firestore.indexes.json.
  // Reads from the server: the cache holds only what screens have loaded, so
  // an offline export would be partial with nothing to say so.
  Future<List<StoredDocument>> _readOwned(String collection, String uid) async {
    final List<StoredDocument> documents = <StoredDocument>[];
    Query<Map<String, dynamic>> page = _firestore
        .collection(collection)
        .where('ownerID', isEqualTo: uid)
        .orderBy(FieldPath.documentId)
        .limit(pageSize);
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await page.get(
        const GetOptions(source: Source.server),
      );
      documents.addAll(<StoredDocument>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          (id: doc.id, data: doc.data()),
      ]);
      if (snapshot.docs.length < pageSize) {
        return documents;
      }
      page = page.startAfterDocument(snapshot.docs.last);
    }
  }

  // Reads from the server so that, offline, deletion fails before it removes
  // anything rather than queueing deletes it cannot confirm.
  Future<void> _deleteOwned(
    String collection,
    String uid, {
    required void Function() beforeCommit,
  }) async {
    final Query<Map<String, dynamic>> query = _firestore
        .collection(collection)
        .where('ownerID', isEqualTo: uid)
        .limit(pageSize);
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get(
        const GetOptions(source: Source.server),
      );
      if (snapshot.docs.isEmpty) {
        return;
      }
      final WriteBatch batch = _firestore.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        batch.delete(doc.reference);
      }
      beforeCommit();
      await batch.commit();
    }
  }

  // clearPersistence only runs on a terminated instance. The plugin builds a
  // fresh native instance, with the same settings, on the next call.
  // A failure leaves the cache behind but must not undo the sign-out.
  // The journal goes with the cache: the writes it names are no longer queued.
  Future<void> _clearLocalCache() async {
    try {
      await _firestore.terminate();
      await _firestore.clearPersistence();
      await _queuedWrites.clear();
    } on FirebaseException catch (e, stack) {
      _report(e, stack, 'clearing the on-device Firestore cache');
    }
  }

  void _report(Object error, StackTrace stack, String context) {
    reportError(error, stack, context: 'while $context');
  }
}
