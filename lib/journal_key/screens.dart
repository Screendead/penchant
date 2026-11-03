import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tracker/crypto/recovery_key.dart';

/// The recovery key as 8 groups of 4, each character in a fixed-width cell so
/// the groups line up without a monospace font.
class RecoveryKeyCard extends StatelessWidget {
  const RecoveryKeyCard({super.key, required this.formatted, this.highlight});

  final String formatted;

  /// 1-based group to emphasise (the confirm step's answer, or a typo).
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<String> groups = RecoveryKey.groupsOf(formatted);

    Widget group(int index) {
      final bool on = highlight == index + 1;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: on ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final String c in groups[index].split(''))
              SizedBox(
                width: 15,
                child: Text(
                  c,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: on ? colors.onPrimaryContainer : colors.onSurface,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Recovery key',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (int row = 0; row < 2; row++) ...[
              if (row == 1) const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (int g = row * 4; g < row * 4 + 4; g++) group(g)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.content, this.bottom});

  final List<Widget> content;
  final List<Widget>? bottom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
            ),
            ...?bottom,
          ],
        ),
      ),
    );
  }
}

TextStyle? _muted(BuildContext context) => Theme.of(context)
    .textTheme
    .bodyMedium
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

/// Timing variant B: the step straight after sign-up.
class RecoveryKeyIntroScreen extends StatelessWidget {
  const RecoveryKeyIntroScreen({
    super.key,
    required this.formatted,
    required this.onSave,
    required this.onLater,
  });

  final String formatted;
  final VoidCallback onSave;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      body: _Body(
        content: [
          const SizedBox(height: 24),
          Icon(Icons.lock_outline, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Your journal is encrypted', style: text.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'What you log is locked with a key that lives on your devices. '
            'We store only the locked copy, so we cannot read your vices or '
            'amounts. We can see when you log.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'If you ever lose every device signed in to iCloud Keychain, this '
            'recovery key is the only way back in. Without it, nobody can '
            'open the journal, including us.',
            style: _muted(context),
          ),
          const SizedBox(height: 20),
          RecoveryKeyCard(formatted: formatted),
          const SizedBox(height: 12),
          Text(
            'You can see it again in Settings > Recovery key.',
            style: _muted(context),
          ),
        ],
        bottom: [
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.download),
            label: const Text('Save recovery key'),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onLater, child: const Text('Later')),
        ],
      ),
    );
  }
}

/// Timing variant A: a card on Today once the journal is worth protecting.
class DeferredRecoveryCard extends StatelessWidget {
  const DeferredRecoveryCard({
    super.key,
    required this.entries,
    required this.days,
    required this.onSave,
    required this.onDismiss,
  });

  final int entries;
  final int days;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      color: colors.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key, color: colors.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Save your recovery key',
                    style: text.titleMedium?.copyWith(color: colors.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '$entries entries over $days days, all encrypted. If you lose '
                'this phone and iCloud Keychain, the recovery key is the only '
                'way back in.',
                style: text.bodyMedium?.copyWith(color: colors.onSecondaryContainer),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Not now')),
                FilledButton.tonal(onPressed: onSave, child: const Text('Save key')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// PDF, Print and Share are stubs in the spike (no plugin for them yet);
/// Copy works.
class SaveRecoveryKeySheet extends StatelessWidget {
  const SaveRecoveryKeySheet({
    super.key,
    required this.formatted,
    required this.onSaved,
  });

  final String formatted;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    Widget option(IconData icon, String title, String subtitle, VoidCallback onTap) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: onTap,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save your recovery key', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Keep it somewhere other than this phone: a password manager, or '
            'printed and put away.',
            style: _muted(context),
          ),
          const SizedBox(height: 16),
          RecoveryKeyCard(formatted: formatted),
          const SizedBox(height: 8),
          option(Icons.picture_as_pdf_outlined, 'Save as PDF', 'To Files, or a password manager', () {}),
          option(Icons.print_outlined, 'Print', 'A paper copy, kept at home', () {}),
          option(Icons.content_copy, 'Copy', 'Clears from the clipboard in 60 seconds', () {
            Clipboard.setData(ClipboardData(text: formatted));
          }),
          option(Icons.ios_share, 'Share', 'AirDrop or Messages to yourself', () {}),
          const SizedBox(height: 8),
          FilledButton(onPressed: onSaved, child: const Text("I've saved it")),
        ],
      ),
    );
  }
}

/// Asks for one group back, so a key that was never written down is caught
/// now rather than on the day it's needed.
class ConfirmGroupScreen extends StatelessWidget {
  const ConfirmGroupScreen({
    super.key,
    required this.group,
    required this.controller,
    required this.onConfirm,
    required this.onShowAgain,
    this.wrong = false,
  });

  final int group;
  final TextEditingController controller;
  final VoidCallback onConfirm;
  final VoidCallback onShowAgain;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Check your copy')),
      body: _Body(
        content: [
          Text('Type group $group of your recovery key', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'From the copy you just saved, not from this screen. Group $group '
            'is the ${_ordinal(group)} block of four characters.',
            style: _muted(context),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int g = 1; g <= RecoveryKey.groups; g++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: g == group ? 28 : 18,
                  height: 8,
                  decoration: BoxDecoration(
                    color: g == group
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: 'Group $group',
              errorText: wrong
                  ? "That isn't group $group. Check the copy you saved; if it "
                        "doesn't match, save the key again."
                  : null,
              errorMaxLines: 3,
            ),
          ),
        ],
        bottom: [
          FilledButton(onPressed: onConfirm, child: const Text('Confirm')),
          TextButton(onPressed: onShowAgain, child: const Text('Show the key again')),
        ],
      ),
    );
  }
}

String _ordinal(int n) =>
    const ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth'][n - 1];

class OpeningJournalScreen extends StatelessWidget {
  const OpeningJournalScreen({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 40, height: 40, child: CircularProgressIndicator()),
              const SizedBox(height: 24),
              Text('Opening your journal', style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                detail ?? "Checking this device's key",
                textAlign: TextAlign.center,
                style: _muted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the typed text was refused, in words.
String? recoveryKeyError(RecoveryKeyParse? parse, {bool wrongJournal = false}) {
  if (wrongJournal) {
    return 'That is a valid recovery key, but not for this journal. Check '
        "it's the key saved for this account.";
  }

  return switch (parse) {
    null || RecoveryKeyOk() => null,
    RecoveryKeyBadCharacter(:final int position, :final String character) =>
      '"$character" (character $position) is never used in a recovery key.',
    RecoveryKeyWrongLength(:final int length) =>
      "That's $length characters; a recovery key has ${RecoveryKey.characters}.",
    RecoveryKeyTypo(position: final int position) =>
      'Character ${(position - 1) % RecoveryKey.groupSize + 1} of group '
          '${(position - 1) ~/ RecoveryKey.groupSize + 1} looks wrong. '
          'The rest checks out.',
    RecoveryKeyTypo() =>
      "That key doesn't check out. More than one character is off; compare "
          'it group by group.',
  };
}

class EnterRecoveryKeyScreen extends StatelessWidget {
  const EnterRecoveryKeyScreen({
    super.key,
    required this.controller,
    required this.onUnlock,
    required this.onNoKey,
    this.error,
    this.busy = false,
  });

  final TextEditingController controller;
  final VoidCallback onUnlock;
  final VoidCallback onNoKey;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Unlock your journal')),
      body: _Body(
        content: [
          Text('This device needs your journal key', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Your other devices pass it on through iCloud Keychain. If none of '
            'them is signed in, enter the recovery key you saved.',
            style: _muted(context),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: 'Recovery key',
              hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
              errorText: error,
              errorMaxLines: 3,
              helperText: error == null
                  ? 'Spaces and dashes are optional; O reads as 0, I and L as 1.'
                  : null,
              helperMaxLines: 2,
            ),
          ),
        ],
        bottom: [
          FilledButton(
            onPressed: busy ? null : onUnlock,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Unlock'),
          ),
          TextButton(onPressed: onNoKey, child: const Text("I don't have my recovery key")),
        ],
      ),
    );
  }
}

class StartNewJournalDialog extends StatelessWidget {
  const StartNewJournalDialog({
    super.key,
    required this.vices,
    required this.entries,
    required this.onCancel,
    required this.onConfirm,
  });

  final int vices;
  final int entries;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: colors.error),
      title: const Text('Start a new journal?'),
      content: Text(
        "Without the recovery key or a device that has the journal key, your "
        "journal can't be opened, by you or by us.\n\n"
        'Starting again permanently deletes its $vices vices and '
        '${NumberFormat.decimalPattern().format(entries)} entries, and makes '
        'a new key and recovery key.\n\n'
        'If the key might be on another device or in a password manager, '
        'look there first.',
      ),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('Keep looking')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.error),
          onPressed: onConfirm,
          child: const Text('Delete and start again'),
        ),
      ],
    );
  }
}

/// Settings > Recovery key. Reads the key from the synced keychain item; on a
/// device this would sit behind Face ID (not in the spike).
class RecoveryKeySettingsScreen extends StatelessWidget {
  const RecoveryKeySettingsScreen({
    super.key,
    required this.formatted,
    required this.confirmed,
    required this.onSave,
    required this.onReplace,
  });

  final String formatted;
  final String? confirmed;
  final VoidCallback onSave;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Recovery key')),
      body: _Body(
        content: [
          RecoveryKeyCard(formatted: formatted),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                confirmed == null ? Icons.error_outline : Icons.check_circle_outline,
                size: 18,
                color: confirmed == null ? colors.error : colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  confirmed == null ? 'Not saved yet' : 'Saved and checked $confirmed',
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('What it does', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Your journal is encrypted on this phone before it syncs. The key '
            'stays in your iCloud Keychain, so your Mac and a new iPhone pick '
            'it up on their own. The recovery key is for when no device has '
            "it: we can't reset it for you.",
            style: _muted(context),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download),
            title: const Text('Save it again'),
            onTap: onSave,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.autorenew),
            title: const Text('Make a new recovery key'),
            subtitle: const Text('The old one stops working. Your entries stay as they are.'),
            onTap: onReplace,
          ),
        ],
      ),
    );
  }
}
