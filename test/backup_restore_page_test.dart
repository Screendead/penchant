import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/backup/backup_page.dart';
import 'package:tracker/backup/backup_service.dart';
import 'package:tracker/backup/restore.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fake_account.dart';
import 'fake_sealer.dart';
import 'backup_fakes.dart';
import 'fakes.dart';

class _Files implements BackupFiles {
  _Files(this.picked);

  Uint8List? picked;
  Object? failWith;

  @override
  Future<Uint8List?> pick() async {
    if (failWith != null) {
      throw failWith!;
    }
    return picked;
  }

  @override
  Future<bool> save(Uint8List bytes, String name) async => true;
}

class _Target implements RestoreTarget {
  final Map<String, Set<String>> owned = <String, Set<String>>{};
  final List<List<RestoreWrite>> batches = <List<RestoreWrite>>[];
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<Set<String>> ownedIDs(String collection, String uid) async =>
      owned[collection] ?? <String>{};

  @override
  Future<void> commit(List<RestoreWrite> writes) async {
    await gate?.future;
    if (failWith != null) {
      throw failWith!;
    }
    batches.add(writes);
  }
}

final Finder _field = find.byKey(RestorePage.keyField);

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump();
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

Future<void> _open(
  WidgetTester tester, {
  required _Files files,
  required _Target target,
  FakeAccount? account,
  FieldSealer? sealer,
  bool noSealer = false,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        e2eeEnabledProvider.overrideWithValue(true),
        accountProvider.overrideWithValue(account ?? FakeAccount()),
        userProvider.overrideWith((ref) => Stream.value(FakeUser(sampleToUid))),
        sealerProvider.overrideWithValue(
          noSealer ? null : (sealer ?? FakeSealer(keyByte: 9)),
        ),
        backupFilesProvider.overrideWithValue(files),
        backupCiphersProvider.overrideWithValue(
          BackupCiphers(aes128: aes128, aes256: aes256),
        ),
        restoreTargetProvider.overrideWithValue(target),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            ref.watch(userProvider);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RestorePage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await _tap(tester, find.text('open'));
}

Future<void> _toKeyStep(WidgetTester tester, Uint8List bytes) async {
  final _Files files = _Files(bytes);
  await _open(tester, files: files, target: _Target());
  await _tap(tester, _button(BackupCopy.choose));
}

void main() {
  late Uint8List bytes;
  late Uint8List unknownBytes;

  setUpAll(() async {
    bytes = await sampleBackup();
    unknownBytes = await sampleBackup(unknown: true);
  });

  testWidgets('choose, key, confirm, progress, done', (tester) async {
    final _Target target = _Target();
    await _open(tester, files: _Files(bytes), target: target);
    expect(find.text(BackupCopy.chooseBody), findsOneWidget);

    await _tap(tester, _button(BackupCopy.choose));
    expect(find.text(BackupCopy.keyPrompt), findsOneWidget);
    expect(_field, findsOneWidget);

    // Wrong shape: refused before anything is opened.
    await _enter(tester, 'ABCD');
    await _tap(tester, _button(BackupCopy.openBackup));
    expect(find.text(RecoveryKeyCopy.wrongLength(4)), findsOneWidget);
    expect(find.text(BackupCopy.checking), findsNothing);

    // A well-formed key that is not this backup's.
    await _enter(tester, RecoveryKey.format(otherRecoveryKey));
    expect(find.text(RecoveryKeyCopy.wrongLength(4)), findsNothing);
    await _tap(tester, _button(BackupCopy.openBackup));
    expect(
      find.text(BackupCopy.failure(BackupFailure.wrongRecoveryKey)),
      findsOneWidget,
    );
    expect(_field, findsOneWidget);

    final Completer<void> gate = Completer<void>();
    target.gate = gate;
    await _enter(tester, RecoveryKey.format(sampleRecoveryKey));
    await _tap(tester, _button(BackupCopy.openBackup));
    expect(find.text(BackupCopy.confirmTitle), findsOneWidget);
    expect(
      find.text(BackupCopy.confirmInto('someone@example.com')),
      findsOneWidget,
    );
    expect(_button(BackupCopy.restore(2)), findsOneWidget);
    expect(target.batches, isEmpty);

    await _tap(tester, _button(BackupCopy.restore(2)));
    expect(find.text(BackupCopy.writing(0, 2)), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    gate.complete();
    await _settle(tester);
    expect(find.text(BackupCopy.doneTitle), findsOneWidget);
    expect(
      find.text(BackupCopy.wrote(<String, int>{'vices': 1, 'activities': 1})),
      findsOneWidget,
    );
    expect(find.text(BackupCopy.newKeyNote), findsOneWidget);
    expect(
      <String>[
        for (final List<RestoreWrite> b in target.batches)
          for (final RestoreWrite w in b) w.collection,
      ],
      <String>['vices', 'activities'],
    );

    await _tap(tester, _button(BackupCopy.done));
    expect(find.text(BackupCopy.doneTitle), findsNothing);
  });

  testWidgets('an unreadable file stays on the first step', (tester) async {
    await _open(
      tester,
      files: _Files(Uint8List.fromList(<int>[1, 2, 3, 4])),
      target: _Target(),
    );
    await _tap(tester, _button(BackupCopy.choose));
    expect(
      find.text(BackupCopy.failure(BackupFailure.notABackup)),
      findsOneWidget,
    );
    expect(_field, findsNothing);
  });

  testWidgets('cancelling the file panel changes nothing', (tester) async {
    await _open(tester, files: _Files(null), target: _Target());
    await _tap(tester, _button(BackupCopy.choose));
    expect(find.text(BackupCopy.chooseBody), findsOneWidget);
    expect(_field, findsNothing);
  });

  testWidgets('a picker failure is reported plainly', (tester) async {
    final _Files files = _Files(null)..failWith = StateError('panel');
    await _open(tester, files: files, target: _Target());
    await _tap(tester, _button(BackupCopy.choose));
    expect(find.text(BackupCopy.pickFailed), findsOneWidget);
  });

  testWidgets('a guest is refused before any file is read', (tester) async {
    final _Files files = _Files(bytes);
    await _open(
      tester,
      files: files,
      target: _Target(),
      account: FakeAccount()..isGuest = true,
    );
    await _tap(tester, _button(BackupCopy.choose));
    expect(find.text(BackupCopy.guestRefused), findsOneWidget);
    expect(_field, findsNothing);
  });

  testWidgets('no journal key loaded is refused', (tester) async {
    await _open(
      tester,
      files: _Files(bytes),
      target: _Target(),
      noSealer: true,
    );
    await _tap(tester, _button(BackupCopy.choose));
    expect(find.text(BackupCopy.noKey), findsOneWidget);
    expect(_field, findsNothing);
  });

  testWidgets('an account that already has a journal is refused', (
    tester,
  ) async {
    await _open(
      tester,
      files: _Files(bytes),
      target: _Target()
        ..owned['activities'] = <String>{'someone-elses', 'another'},
    );
    await _tap(tester, _button(BackupCopy.choose));
    await _enter(tester, RecoveryKey.format(sampleRecoveryKey));
    await _tap(tester, _button(BackupCopy.openBackup));
    expect(
      find.text(BackupCopy.notEmpty(<String, int>{'activities': 2})),
      findsOneWidget,
    );
    expect(find.text(BackupCopy.confirmTitle), findsNothing);
  });

  testWidgets('a collection this version does not know is refused', (
    tester,
  ) async {
    await _toKeyStep(tester, unknownBytes);
    await _enter(tester, RecoveryKey.format(sampleRecoveryKey));
    await _tap(tester, _button(BackupCopy.openBackup));
    expect(find.text(BackupCopy.unknownCollection), findsOneWidget);
    expect(find.text(BackupCopy.confirmTitle), findsNothing);
  });

  testWidgets('a cut-short write shows what was written', (tester) async {
    final _Target target = _Target();
    await _open(tester, files: _Files(bytes), target: target);
    await _tap(tester, _button(BackupCopy.choose));
    await _enter(tester, RecoveryKey.format(sampleRecoveryKey));
    await _tap(tester, _button(BackupCopy.openBackup));
    target.failWith = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await _tap(tester, _button(BackupCopy.restore(2)));
    expect(find.text(BackupCopy.stoppedTitle), findsOneWidget);
    expect(find.text(BackupCopy.refused), findsOneWidget);
  });

  testWidgets('Choose another file returns to the first step', (tester) async {
    await _toKeyStep(tester, bytes);
    await _enter(tester, 'ABCD');
    await _tap(
      tester,
      find.widgetWithText(TextButton, BackupCopy.chooseAnother),
    );
    expect(find.text(BackupCopy.chooseBody), findsOneWidget);
    expect(_field, findsNothing);
  });
}
