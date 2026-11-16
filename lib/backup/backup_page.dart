import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/backup/backup_service.dart';
import 'package:tracker/backup/restore.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/page_transitions.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

class BackupCopy {
  static const String pageTitle = 'Backup';
  static const String settingsRow = 'Backup';
  static const String settingsSubtitle = 'Save or restore an encrypted copy';
  static const String saveTitle = 'Save a backup';
  static const String saveBody =
      'One encrypted file holding every habit, entry, day note and urge in '
      'your account. You choose where it goes: Files, iCloud Drive or any '
      'folder. Nothing is kept anywhere else.';
  static const String keyLine =
      'It opens only with your recovery key, in Settings > Account > '
      'Recovery key. Without that key the file is useless, to anyone.';
  static const String notInIt =
      'Not in it: what stays on this device, such as Health values, places, '
      'an experiment plan and letters.';
  static String lastSaved(DateTime? at) => at == null
      ? 'No backup saved from this device yet.'
      : 'Last saved from this device on ${DateFormat.yMMMd().format(at)}.';
  static const String save = 'Save a backup';
  static const String preparing = 'Preparing…';
  static const String saved = 'Backup saved.';
  static const String noKey =
      "This account's journal key hasn't loaded yet. Try again in a moment.";
  static const String unsynced =
      "Some entries on this device haven't reached the server yet, so they "
      "wouldn't be in the backup. Connect to the internet, then try again.";
  static const String selfCheckFailed =
      "The new backup didn't open with this device's recovery key, so it "
      "wasn't offered for saving. Check Settings > Account > Recovery key.";
  static String saveFailed(String reason) => "Couldn't save a backup. $reason";

  static const String restoreSection = 'Restore';
  static const String restoreTitle = 'Restore from a backup';
  static const String restoreBody =
      "Writes a backup's journal into this account, if it has nothing in it "
      "yet. You'll need the recovery key that was current when the backup "
      'was saved.';
  static const String restoreOpen = 'Restore from a backup…';
  static const String guestRefused =
      'Restore writes only into an account with an email and password: a '
      "guest's journal is deleted when it signs out. Save this journal to an "
      'account first, under Account.';

  static const String choose = 'Choose a backup file';
  static const String chooseBody =
      'Pick the file you saved. Nothing is written until you have seen what '
      'it holds and said so.';
  static String fileFrom(DateTime at) =>
      'Backup saved on ${DateFormat.yMMMd().add_jm().format(at.toLocal())}.';
  static const String keyPrompt =
      'Enter the recovery key that was current when this backup was saved.';
  static const String openBackup = 'Open backup';
  static const String checking = 'Checking every document in the backup…';
  static const String chooseAnother = 'Choose another file';

  static String failure(BackupFailure failure) => switch (failure) {
    BackupFailure.notABackup => "This file isn't a Penchant backup.",
    BackupFailure.newerFormat =>
      'This backup was saved by a newer version of Penchant. Update the app, '
          'then try again.',
    BackupFailure.incomplete =>
      'This backup file is incomplete: it was cut short while being copied '
          'or saved. Try another copy.',
    BackupFailure.damaged =>
      "This backup file is damaged: its checksum doesn't match its contents. "
          'Try another copy.',
    BackupFailure.wrongRecoveryKey =>
      "That recovery key doesn't open this backup. Use the key that was "
          'current when it was saved.',
    BackupFailure.keyMismatch =>
      "This backup doesn't hold together: the key inside it isn't the one it "
          'names, so it may have been altered. Nothing was written.',
    BackupFailure.modified =>
      'This backup has been changed since it was saved, so it cannot be '
          'trusted. Nothing was written.',
  };
  static const String unknownCollection =
      "This backup holds data this version of Penchant can't restore. Update "
      'the app, then try again. Nothing was written.';
  static String notEmpty(Map<String, int> counts) =>
      'This account already has a journal: ${describeCounts(counts)}. '
      'Restore writes only into an account with nothing in it, so nothing is '
      'mixed or overwritten. Nothing was written.';
  static const String pickFailed = "Couldn't read that file.";

  static const String confirmTitle = 'Restore this journal?';
  static String confirmInto(String? email) =>
      email == null ? 'Into this account:' : 'Into $email:';
  static const String resealed =
      "Each one is sealed again with this account's own journal key.";
  static String alreadyThere(int n) =>
      '${formatCount(n)} already here from an earlier restore of this backup, '
      'left as they are.';
  static String restore(int n) =>
      'Restore ${formatCount(n)} ${pluralWord(n, one: 'document', other: 'documents')}';
  static const String cancel = 'Cancel';

  static String writing(int done, int total) =>
      'Writing ${formatCount(done)} of ${formatCount(total)}…';

  static const String doneTitle = 'Journal restored';
  static const String stoppedTitle = 'Restore stopped';
  static String wrote(Map<String, int> counts) => counts.isEmpty
      ? 'Nothing new was written.'
      : 'Written: ${describeCounts(counts)}.';
  static String stopped(int done, int total) =>
      'Stopped after ${formatCount(done)} of ${formatCount(total)}: the '
      'connection or the server failed. Run Restore again with the same file '
      'and key: it writes only what is missing, with nothing duplicated.';
  static const String refused =
      'The server refused part of the backup, so running Restore again would '
      'stop at the same place. What was written stays; nothing is '
      'duplicated.';
  static String trimmed(int n) =>
      '${formatCount(n)} ${pluralWord(n, one: 'document', other: 'documents')} '
      'had fields this version no longer uses; those fields were left out.';
  static const String newKeyNote =
      'This account keeps its own recovery key, in Settings > Account > '
      "Recovery key. The backup's key opens only the backup: save this "
      "account's key, then save a new backup.";
  static const String done = 'Done';

  static String skipped(SkipReason reason, int n) {
    final String what = '${formatCount(n)} not written';
    return switch (reason) {
      SkipReason.earlierKey =>
        '$what: sealed under an earlier journal key, which this backup '
            "doesn't hold.",
      SkipReason.habitMissing =>
        "$what: their habit isn't in the backup or couldn't be restored.",
      SkipReason.noTime => '$what: no time recorded.',
      SkipReason.badAmount =>
        "$what: a quantity the app no longer accepts, such as 0.",
      SkipReason.badDay => '$what: a day note with an unreadable date.',
      SkipReason.tooLong => '$what: too long to seal.',
    };
  }

  static const String offerTitle = 'Save a backup';
  static const String offerBody =
      'Once a month: one encrypted file of your journal, kept where you '
      'choose. It opens only with your recovery key.';
  static const String notNow = 'Not now';
  static const String offerAction = 'Save backup';
}

const Map<String, (String, String)> _nouns = <String, (String, String)>{
  'vices': ('habit', 'habits'),
  'activities': ('entry', 'entries'),
  'dayNotes': ('day note', 'day notes'),
  'urges': ('urge', 'urges'),
};

/// "2 habits, 140 entries", in [restorableCollections] order.
String describeCounts(Map<String, int> counts) => <String>[
  for (final String collection in <String>[
    ...restorableCollections,
    ...counts.keys.where((String c) => !restorableCollections.contains(c)),
  ])
    if ((counts[collection] ?? 0) > 0)
      '${formatCount(counts[collection]!)} ${switch (_nouns[collection]) {
        (final String one, final String other) => pluralWord(counts[collection]!, one: one, other: other),
        null => collection,
      }}',
].join(', ');

Widget _muted(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: DialSpace.xs),
  child: Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: DialColors.of(context).muted),
  ),
);

Widget _section(BuildContext context, String title, List<Widget> body) =>
    DialCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(DialSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              ...body,
            ],
          ),
        ),
      ],
    );

Widget _errorText(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(6, DialSpace.s, 6, 0),
  child: Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  ),
);

/// Settings > Account > Backup: save one, or restore one.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  static const String route = '/settings/backup';

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final BackupKey? key = ref.read(backupKeyProvider);
    if (key == null) {
      setState(() => _error = BackupCopy.noKey);
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final DateTime now = DateTime.now();
      final Uint8List bytes = await makeBackup(
        account: ref.read(accountProvider),
        key: key,
        ciphers: ref.read(backupCiphersProvider),
        now: now,
      );
      if (await ref
          .read(backupFilesProvider)
          .save(bytes, backupFileName(now))) {
        await ref.read(backupDatesProvider.notifier).markSaved(now);
        messenger.showSnackBar(const SnackBar(content: Text(BackupCopy.saved)));
      }
    } on UnsyncedEntriesException {
      error = BackupCopy.unsynced;
    } on BackupSelfCheckFailed catch (e, stack) {
      reportError(e.cause, stack, context: 'while checking a new backup');
      error = BackupCopy.selfCheckFailed;
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving a backup');
      error = BackupCopy.saveFailed(authErrorMessage(e));
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read live: linking a guest leaves userProvider's User anonymous.
    ref.watch(userProvider.select((v) => v.value?.uid));
    final bool guest = ref.watch(accountProvider).isGuest;
    return BackupSaveView(
      lastSaved: ref.watch(backupDatesProvider).savedAt,
      busy: _busy,
      error: _error,
      guest: guest,
      onSave: _save,
      onRestore: () => Navigator.of(
        context,
      ).push(DialPageRoute<void>(builder: (_) => const RestorePage())),
    );
  }
}

class BackupSaveView extends StatelessWidget {
  const BackupSaveView({
    super.key,
    required this.lastSaved,
    required this.busy,
    required this.guest,
    required this.onSave,
    required this.onRestore,
    this.error,
  });

  final DateTime? lastSaved;
  final bool busy;
  final bool guest;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => CardPage(
    title: BackupCopy.pageTitle,
    children: <Widget>[
      _section(context, BackupCopy.saveTitle, <Widget>[
        _muted(context, BackupCopy.saveBody),
        _muted(context, BackupCopy.keyLine),
        _muted(context, BackupCopy.notInIt),
        const SizedBox(height: DialSpace.m),
        Text(
          BackupCopy.lastSaved(lastSaved),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ]),
      if (error != null) _errorText(context, error!),
      const SizedBox(height: DialSpace.m),
      FilledButton(
        onPressed: busy ? null : onSave,
        child: Text(busy ? BackupCopy.preparing : BackupCopy.save),
      ),
      const CardSectionLabel(BackupCopy.restoreSection),
      _section(context, BackupCopy.restoreTitle, <Widget>[
        _muted(
          context,
          guest ? BackupCopy.guestRefused : BackupCopy.restoreBody,
        ),
      ]),
      if (!guest) ...<Widget>[
        const SizedBox(height: DialSpace.m),
        OutlinedButton(
          onPressed: busy ? null : onRestore,
          child: const Text(BackupCopy.restoreOpen),
        ),
      ],
    ],
  );
}

enum _Step { pick, key, checking, confirm, writing, done }

/// Choose a file, enter its recovery key, see what will be written, write it.
class RestorePage extends ConsumerStatefulWidget {
  const RestorePage({super.key});

  static const Key keyField = Key('restore-recovery-field');

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  _Step _step = _Step.pick;
  Uint8List? _file;
  BackupHeader? _header;
  RestorePlan? _plan;
  int _alreadyThere = 0;
  RestoreResult? _result;
  String? _error;
  int _done = 0;
  int _total = 0;
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  // A guest, or a journal whose key has not loaded, is refused before any
  // file is read.
  String? _refusal() {
    if (ref.read(accountProvider).isGuest) {
      return BackupCopy.guestRefused;
    }
    if (ref.read(sealerProvider) == null && ref.read(e2eeEnabledProvider)) {
      return BackupCopy.noKey;
    }
    return null;
  }

  Future<void> _pick() async {
    final String? refusal = _refusal();
    if (refusal != null) {
      setState(() => _error = refusal);
      return;
    }
    setState(() => _error = null);
    final Uint8List? file;
    try {
      file = await ref.read(backupFilesProvider).pick();
    } catch (e, stack) {
      reportError(e, stack, context: 'while picking a backup file');
      setState(() => _error = BackupCopy.pickFailed);
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    try {
      final BackupHeader header = BackupFile.readHeader(file);
      setState(() {
        _file = file;
        _header = header;
        _step = _Step.key;
      });
    } on BackupException catch (e) {
      setState(() => _error = BackupCopy.failure(e.failure));
    }
  }

  Future<void> _open() async {
    final RecoveryKeyParse parse = RecoveryKey.parse(_typed.text);
    final String? problem = recoveryKeyProblem(parse);
    if (problem != null || parse is! RecoveryKeyOk) {
      setState(() => _error = problem);
      return;
    }
    final String? refusal = _refusal();
    final String? uid = ref.read(userProvider).value?.uid;
    final FieldSealer? destination = ref.read(sealerProvider);
    if (refusal != null || uid == null || destination == null) {
      setState(() => _error = refusal ?? BackupCopy.noKey);
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.checking;
    });
    final BackupCiphers ciphers = ref.read(backupCiphersProvider);
    String? error;
    try {
      final OpenedBackup backup = await BackupFile.open(
        _file!,
        recoveryKey: parse.key,
        aes128: ciphers.aes128,
        aes256: ciphers.aes256,
      );
      final RestorePlan plan = await planRestore(
        backup,
        destinationUid: uid,
        destination: destination,
        aes256: ciphers.aes256,
      );
      final ({RestorePlan plan, int alreadyThere}) checked = checkAgainst(
        plan,
        await existingIDs(ref.read(restoreTargetProvider), uid),
      );
      _plan = plan;
      _alreadyThere = checked.alreadyThere;
      _total = checked.plan.total;
    } on BackupException catch (e) {
      error = BackupCopy.failure(e.failure);
    } on UnknownCollection {
      error = BackupCopy.unknownCollection;
    } on AccountNotEmpty catch (e) {
      error = BackupCopy.notEmpty(e.counts);
    } catch (e, stack) {
      reportError(e, stack, context: 'while opening a backup');
      error = BackupCopy.saveFailed(authErrorMessage(e));
    }
    if (mounted) {
      setState(() {
        _error = error;
        _step = error == null ? _Step.confirm : _Step.key;
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _step = _Step.writing;
      _done = 0;
    });
    RestoreResult? result;
    String? error;
    try {
      // Checked again just before writing: something may have been logged in
      // this account since the confirmation was shown.
      result = await runRestore(
        _plan!,
        ref.read(restoreTargetProvider),
        onProgress: (int done, int total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
    } on AccountNotEmpty catch (e) {
      error = BackupCopy.notEmpty(e.counts);
    } catch (e, stack) {
      reportError(e, stack, context: 'while restoring a backup');
      error = BackupCopy.saveFailed(authErrorMessage(e));
    }
    if (result?.stoppedBy case final Object cause) {
      reportError(cause, StackTrace.current, context: 'while restoring');
    }
    if (mounted) {
      setState(() {
        _result = result;
        _error = error;
        _step = result == null ? _Step.confirm : _Step.done;
      });
    }
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
    _Step.pick => CardPage(
      title: BackupCopy.restoreTitle,
      children: <Widget>[
        _section(context, BackupCopy.choose, <Widget>[
          _muted(context, BackupCopy.chooseBody),
        ]),
        if (_error != null) _errorText(context, _error!),
        const SizedBox(height: DialSpace.m),
        FilledButton(onPressed: _pick, child: const Text(BackupCopy.choose)),
      ],
    ),
    _Step.key || _Step.checking => CardPage(
      title: BackupCopy.restoreTitle,
      children: <Widget>[
        _section(context, BackupCopy.fileFrom(_header!.createdAt), <Widget>[
          _muted(context, BackupCopy.keyPrompt),
        ]),
        const SizedBox(height: DialSpace.m),
        TextField(
          key: RestorePage.keyField,
          controller: _typed,
          enabled: _step == _Step.key,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            fontFamily: DialFonts.mono,
            fontFeatures: DialFonts.tabular,
            fontSize: 20,
            letterSpacing: 1.5,
            height: 1.4,
          ),
          decoration: InputDecoration(
            labelText: RecoveryKeyCopy.entryLabel,
            errorText: _error,
            errorMaxLines: 5,
          ),
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
        ),
        const SizedBox(height: DialSpace.xl),
        if (_step == _Step.checking)
          const _Progress(text: BackupCopy.checking)
        else ...<Widget>[
          FilledButton(
            onPressed: _open,
            child: const Text(BackupCopy.openBackup),
          ),
          const SizedBox(height: DialSpace.xs),
          TextButton(
            onPressed: () => setState(() {
              _step = _Step.pick;
              _file = null;
              _header = null;
              _error = null;
              _typed.clear();
            }),
            child: const Text(BackupCopy.chooseAnother),
          ),
        ],
      ],
    ),
    _Step.confirm => RestoreConfirmView(
      email: ref.watch(userProvider).value?.email,
      backupDate: _header!.createdAt,
      plan: _plan!,
      toWrite: _total,
      alreadyThere: _alreadyThere,
      error: _error,
      onRestore: _restore,
      onCancel: () => Navigator.of(context).pop(),
    ),
    // No way back while writing: the result is the only report of it.
    _Step.writing => PopScope(
      canPop: false,
      child: CardPage(
        title: BackupCopy.restoreTitle,
        children: <Widget>[
          const SizedBox(height: DialSpace.xl),
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: DialSpace.s),
          Semantics(
            liveRegion: true,
            child: Text(BackupCopy.writing(_done, _total)),
          ),
        ],
      ),
    ),
    _Step.done => RestoreResultView(
      result: _result!,
      onDone: () => Navigator.of(context).pop(),
    ),
  };
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: DialSpace.s),
      Expanded(child: Text(text)),
    ],
  );
}

/// What a restore will write, shown before anything is.
class RestoreConfirmView extends StatelessWidget {
  const RestoreConfirmView({
    super.key,
    required this.email,
    required this.backupDate,
    required this.plan,
    required this.toWrite,
    required this.alreadyThere,
    required this.onRestore,
    required this.onCancel,
    this.error,
  });

  final String? email;
  final DateTime backupDate;

  /// Everything the backup restores, before what is already here is left out.
  final RestorePlan plan;
  final int toWrite;
  final int alreadyThere;
  final String? error;
  final VoidCallback onRestore;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => CardPage(
    title: BackupCopy.confirmTitle,
    children: <Widget>[
      _section(context, BackupCopy.fileFrom(backupDate), <Widget>[
        _muted(context, BackupCopy.confirmInto(email)),
        Padding(
          padding: const EdgeInsets.only(top: DialSpace.xs),
          child: Text(
            '${describeCounts(<String, int>{for (final String c in restorableCollections) c: plan.count(c)})}.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        if (alreadyThere > 0)
          _muted(context, BackupCopy.alreadyThere(alreadyThere)),
        for (final MapEntry<SkipReason, int>(:key, :value)
            in plan.skipped.entries)
          _muted(context, BackupCopy.skipped(key, value)),
        if (plan.trimmed > 0) _muted(context, BackupCopy.trimmed(plan.trimmed)),
        _muted(context, BackupCopy.resealed),
      ]),
      if (error != null) _errorText(context, error!),
      const SizedBox(height: DialSpace.xl),
      FilledButton(
        onPressed: onRestore,
        child: Text(BackupCopy.restore(toWrite)),
      ),
      const SizedBox(height: DialSpace.xs),
      TextButton(onPressed: onCancel, child: const Text(BackupCopy.cancel)),
    ],
  );
}

/// What a restore wrote, what it left out and why, and what to do next.
class RestoreResultView extends StatelessWidget {
  const RestoreResultView({
    super.key,
    required this.result,
    required this.onDone,
  });

  final RestoreResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final bool stopped = result.stoppedBy != null;
    return CardPage(
      title: stopped ? BackupCopy.stoppedTitle : BackupCopy.doneTitle,
      children: <Widget>[
        _section(context, BackupCopy.wrote(result.written), <Widget>[
          if (stopped)
            _muted(context, switch (result.stoppedBy) {
              FirebaseException(code: 'permission-denied') =>
                BackupCopy.refused,
              _ => BackupCopy.stopped(result.writtenTotal, result.planned),
            }),
          if (result.alreadyThere > 0)
            _muted(context, BackupCopy.alreadyThere(result.alreadyThere)),
          for (final MapEntry<SkipReason, int>(:key, :value)
              in result.skipped.entries)
            _muted(context, BackupCopy.skipped(key, value)),
          if (result.trimmed > 0)
            _muted(context, BackupCopy.trimmed(result.trimmed)),
        ]),
        if (!stopped)
          _section(context, RecoveryKeyCopy.pageTitle, <Widget>[
            _muted(context, BackupCopy.newKeyNote),
          ]),
        const SizedBox(height: DialSpace.xl),
        FilledButton(onPressed: onDone, child: const Text(BackupCopy.done)),
      ],
    );
  }
}

/// Today's quiet monthly offer; never a notification.
class BackupOfferCard extends ConsumerWidget {
  const BackupOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(e2eeEnabledProvider) ||
        ref.watch(backupKeyProvider) == null) {
      return const SizedBox.shrink();
    }
    final RecoveryKeyStatus? status = ref.watch(recoveryKeyStatusProvider);
    final bool due = backupOfferDue(
      recoveryKeySaved: status?.saved ?? false,
      keyCreatedAt: status?.keyCreatedAt,
      dates: ref.watch(backupDatesProvider),
      today: ref.watch(todayProvider),
    );
    if (!due) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DialSpace.s),
      child: DialCard(
        top: 0,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, DialSpace.m, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StrokeIcon(
                      DialGlyph.lock,
                      size: 20,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: DialSpace.xs),
                    Expanded(
                      child: Text(
                        BackupCopy.offerTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _muted(context, BackupCopy.offerBody),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => ref
                          .read(backupDatesProvider.notifier)
                          .dismissOffer(DateTime.now()),
                      child: const Text(BackupCopy.notNow),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(BackupPage.route),
                      child: const Text(BackupCopy.offerAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
