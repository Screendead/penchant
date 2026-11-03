import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/journal_key_provider.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/migrator.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/journal_key/screens.dart';
import 'package:tracker/providers/user_provider.dart';

/// When the recovery key is first offered: at sign-up with Later (B), or as
/// a card on Today after a week (A). Built both ways so Jack can pick.
enum RecoveryPrompt { atSignUp, deferred }

const RecoveryPrompt recoveryPrompt =
    String.fromEnvironment('RECOVERY_PROMPT') == 'deferred'
    ? RecoveryPrompt.deferred
    : RecoveryPrompt.atSignUp;

/// Between sign-in and Homepage: opens the journal key, or asks for it.
class JournalGate extends ConsumerWidget {
  const JournalGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? user = ref.watch(userProvider).value;
    final AsyncValue<JournalKeyState?> key = ref.watch(journalKeyProvider);

    if (user == null) {
      return const OpeningJournalScreen();
    }

    return switch (key) {
      AsyncError(:final Object error) => _KeyErrorScreen(message: '$error'),
      AsyncValue(value: KeyError(:final String message)) => _KeyErrorScreen(message: message),
      AsyncValue(value: KeyNeedsSetup()) => _SetUp(uid: user.uid),
      AsyncValue(value: KeyNeedsUnlock()) => _Unlock(uid: user.uid),
      AsyncValue(value: final KeyReady ready) => _Migrate(
        uid: user.uid,
        ready: ready,
        child: child,
      ),
      _ => const OpeningJournalScreen(),
    };
  }
}

class _KeyErrorScreen extends ConsumerWidget {
  const _KeyErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(journalKeyProvider),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SetUp extends ConsumerStatefulWidget {
  const _SetUp({required this.uid});

  final String uid;

  @override
  ConsumerState<_SetUp> createState() => _SetUpState();
}

class _SetUpState extends ConsumerState<_SetUp> {
  KeyReady? minted;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final JournalKeyEvents events = ref.read(journalKeyEventsProvider);
    try {
      final KeyReady ready = await ref.read(keyServiceProvider).setUp(widget.uid);
      if (recoveryPrompt == RecoveryPrompt.atSignUp && mounted) {
        setState(() => minted = ready);
      } else {
        events.push(widget.uid, ready);
      }
    } on KeyServiceRefused {
      // Another device registered a key first: ask for it, never mint.
      events.push(widget.uid, const KeyNeedsUnlock());
    } catch (e) {
      events.push(widget.uid, KeyError('Could not set up your journal: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final KeyReady? ready = minted;

    if (ready == null) {
      return const OpeningJournalScreen(detail: 'Making your journal key');
    }

    void done() => ref.read(journalKeyEventsProvider).push(widget.uid, ready);

    return RecoveryKeyIntroScreen(
      formatted: ready.stored.recoveryKey!,
      onLater: done,
      onSave: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (BuildContext sheet) => SaveRecoveryKeySheet(
          formatted: ready.stored.recoveryKey!,
          onSaved: () {
            Navigator.of(sheet).pop();
            done();
          },
        ),
      ),
    );
  }
}

class _Unlock extends ConsumerStatefulWidget {
  const _Unlock({required this.uid});

  final String uid;

  @override
  ConsumerState<_Unlock> createState() => _UnlockState();
}

class _UnlockState extends ConsumerState<_Unlock> {
  final TextEditingController controller = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() => busy = true);
    try {
      final UnlockResult result = await ref
          .read(keyServiceProvider)
          .unlock(widget.uid, controller.text);
      switch (result) {
        case Unlocked(:final KeyReady state):
          ref.read(journalKeyEventsProvider).push(widget.uid, state);
        case UnlockRejected(:final RecoveryKeyParse? parse):
          setState(() => error = recoveryKeyError(parse, wrongJournal: parse == null));
      }
    } catch (e) {
      setState(() => error = 'Could not check the key: $e');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _startOver() async {
    final String uid = widget.uid;
    final KeyService service = ref.read(keyServiceProvider);
    final JournalKeyEvents events = ref.read(journalKeyEventsProvider);
    final (int vices, int entries) = await _counts(uid);
    if (!mounted) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => StartNewJournalDialog(
        vices: vices,
        entries: entries,
        onCancel: () => Navigator.of(dialog).pop(false),
        onConfirm: () => Navigator.of(dialog).pop(true),
      ),
    );
    if (confirmed != true) {
      return;
    }

    events.push(
      uid,
      await service.startOver(uid, deleteJournal: () => deleteJournal(uid)),
    );
  }

  @override
  Widget build(BuildContext context) => EnterRecoveryKeyScreen(
    controller: controller,
    error: error,
    busy: busy,
    onUnlock: _unlock,
    onNoKey: _startOver,
  );
}

Future<(int, int)> _counts(String uid) async {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AggregateQuerySnapshot vices = await db
      .collection('vices')
      .where('ownerID', isEqualTo: uid)
      .count()
      .get();
  final AggregateQuerySnapshot activities = await db
      .collection('activities')
      .where('ownerID', isEqualTo: uid)
      .count()
      .get();
  return (vices.count ?? 0, activities.count ?? 0);
}

/// Every vice and activity the user owns, so no ciphertext outlives its key.
Future<void> deleteJournal(String uid) async {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  for (final String collection in <String>['activities', 'vices']) {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> page = await db
          .collection(collection)
          .where('ownerID', isEqualTo: uid)
          .limit(JournalMigrator.pageSize)
          .get(const GetOptions(source: Source.server));
      if (page.docs.isEmpty) {
        break;
      }
      final WriteBatch batch = db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

/// Runs the first-launch migrator once the key is ready; the journal shows
/// meanwhile, since the parsers read both shapes.
class _Migrate extends ConsumerStatefulWidget {
  const _Migrate({required this.uid, required this.ready, required this.child});

  final String uid;
  final KeyReady ready;
  final Widget child;

  @override
  ConsumerState<_Migrate> createState() => _MigrateState();
}

class _MigrateState extends ConsumerState<_Migrate> {
  @override
  void initState() {
    super.initState();
    JournalMigrator(cipher: widget.ready.cipher, store: ref.read(keyStoreProvider))
        .run(widget.uid)
        .then(
          (MigrationReport report) => debugPrint('E2EE $report'),
          onError: (Object e) => debugPrint('E2EE migration failed: ${e.runtimeType}'),
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Settings > Recovery key, for the open journal.
class RecoveryKeySettingsRoute extends ConsumerWidget {
  const RecoveryKeySettingsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final JournalKeyState? key = ref.watch(journalKeyProvider).value;
    final String? formatted = key is KeyReady ? key.stored.recoveryKey : null;

    if (formatted == null) {
      return const OpeningJournalScreen();
    }

    return RecoveryKeySettingsScreen(
      formatted: formatted,
      confirmed: null,
      onSave: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (BuildContext sheet) => SaveRecoveryKeySheet(
          formatted: formatted,
          onSaved: () => Navigator.of(sheet).pop(),
        ),
      ),
      // Re-wrapping under a new recovery key (keys/{uid}.recoveryWrap) is
      // allowed by the rules but not built in the spike.
      onReplace: () {},
    );
  }
}
