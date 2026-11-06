import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

class RecoveryKeyCopy {
  static const String cardTitle = 'Save your recovery key';
  static const String cardBody =
      'Your entries are encrypted on this phone. If you lose it and your '
      'iCloud Keychain, the recovery key is the only way back in.';
  static const String notNow = 'Not now';
  static const String saveKey = 'Save key';
  static const String pageTitle = 'Recovery key';
  static const String settingsRow = 'Recovery key';
  static const String settingsSubtitle = 'Opens your journal on a new device';
  static const String intro =
      'Keep it somewhere other than this phone: a password manager, or '
      'printed and put away.';
  static const String noKey =
      'This device has no recovery key yet. One is made with your journal key '
      'and shows here.';
  static const String copy = 'Copy';
  static const String copied = 'Recovery key copied';
  static const String share = 'Share';
  static const String shareSubject = 'Penchant recovery key';
  static const String savedIt = "I've saved it";
  static const String confirmTitle = 'Check your copy';
  static String confirmPrompt(int group) =>
      'From the copy you just saved, type group $group, the last block of '
      'four characters.';
  static String confirmLabel(int group) => 'Group $group';
  static const String confirm = 'Confirm';
  static String confirmWrong(int group) =>
      "That doesn't match group $group. Check your saved copy.";
  static const String showAgain = 'Show the key again';
  static const String checked = 'Recovery key checked';
  static const String entryTitle = 'Unlock your journal';
  static const String entryHeading = 'This device needs your journal key';
  static const String entryBody =
      'Your other devices pass it on through iCloud Keychain. If none of them '
      'is signed in, enter the recovery key you saved.';
  static const String entryLabel = 'Recovery key';
  static const String unlock = 'Unlock';
  static String badCharacter(String c, int position) =>
      '"$c" at character $position is not used in recovery keys.';
  static String wrongLength(int length) =>
      'A recovery key has ${RecoveryKey.characters} characters; this has '
      '$length.';
  static String typoAt(int inGroup, int group) =>
      'Character $inGroup of group $group looks wrong. The rest checks out.';
  static const String typo =
      'This is not a valid recovery key. Check it against your saved copy.';
  static const String notThisJournal =
      'That is a recovery key, but for a different journal.';
}

/// The dismissible offer on Today, shown once [recoveryCardDue] says so.
class RecoveryKeyCard extends ConsumerWidget {
  const RecoveryKeyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool due = recoveryCardDue(
      ref.watch(recoveryKeyStatusProvider),
      ref.watch(todayProvider),
    );
    if (!due || ref.watch(recoveryCardHiddenProvider)) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
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
                        RecoveryKeyCopy.cardTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    RecoveryKeyCopy.cardBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () {
                        ref.read(recoveryCardHiddenProvider.notifier).hide();
                        ref.read(recoveryKeyActionsProvider).dismissCard();
                      },
                      child: const Text(RecoveryKeyCopy.notNow),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                      ),
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(RecoveryKeyPage.route),
                      child: const Text(RecoveryKeyCopy.saveKey),
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

class _KeyGroups extends StatelessWidget {
  const _KeyGroups(this.groups);

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    return Semantics(
      label: 'Recovery key: ${groups.join(', ')}',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: DialSpace.xs,
        runSpacing: DialSpace.xs,
        children: <Widget>[
          for (final String group in groups)
            Container(
              width: 74,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                group,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: DialFonts.mono,
                  fontFeatures: DialFonts.tabular,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows the recovery key with Copy and Share, then asks for its last group
/// back. Reached from Today's card and from Account settings.
class RecoveryKeyPage extends ConsumerStatefulWidget {
  const RecoveryKeyPage({super.key});

  static const String route = '/settings/recovery-key';
  static const Key confirmField = Key('recovery-confirm-field');

  @override
  ConsumerState<RecoveryKeyPage> createState() => _RecoveryKeyPageState();
}

class _RecoveryKeyPageState extends ConsumerState<RecoveryKeyPage> {
  bool _confirming = false;
  String? _error;
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _confirm(List<String> groups) async {
    if (RecoveryKey.normalise(_typed.text) != groups.last) {
      setState(() => _error = RecoveryKeyCopy.confirmWrong(groups.length));
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    ref.read(recoveryCardHiddenProvider.notifier).hide();
    await ref.read(recoveryKeyActionsProvider).markSaved();
    messenger.showSnackBar(
      const SnackBar(content: Text(RecoveryKeyCopy.checked)),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final RecoveryKeyStatus? status = ref.watch(recoveryKeyStatusProvider);
    if (status == null) {
      return const CardPage(
        title: RecoveryKeyCopy.pageTitle,
        children: <Widget>[CardFoot(RecoveryKeyCopy.noKey)],
      );
    }
    final List<String> groups = RecoveryKey.groupsOf(status.formatted);
    return _confirming ? _confirmStep(groups) : _showStep(status, groups);
  }

  Widget _showStep(RecoveryKeyStatus status, List<String> groups) {
    final ThemeData theme = Theme.of(context);
    return CardPage(
      title: RecoveryKeyCopy.pageTitle,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, DialSpace.xs, 6, 0),
          child: Text(
            RecoveryKeyCopy.intro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DialColors.of(context).muted,
            ),
          ),
        ),
        DialCard(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(DialSpace.m),
              child: _KeyGroups(groups),
            ),
          ],
        ),
        const SizedBox(height: DialSpace.m),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                child: const Text(RecoveryKeyCopy.copy),
                onPressed: () async {
                  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                    context,
                  );
                  await Clipboard.setData(
                    ClipboardData(text: status.formatted),
                  );
                  messenger.showSnackBar(
                    const SnackBar(content: Text(RecoveryKeyCopy.copied)),
                  );
                },
              ),
            ),
            const SizedBox(width: DialSpace.s),
            Expanded(
              child: Builder(
                builder: (BuildContext context) => OutlinedButton(
                  child: const Text(RecoveryKeyCopy.share),
                  onPressed: () {
                    final RenderBox? box =
                        context.findRenderObject() as RenderBox?;
                    SharePlus.instance.share(
                      ShareParams(
                        text: status.formatted,
                        subject: RecoveryKeyCopy.shareSubject,
                        sharePositionOrigin: box == null
                            ? null
                            : box.localToGlobal(Offset.zero) & box.size,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DialSpace.xl),
        FilledButton(
          onPressed: () => setState(() {
            _confirming = true;
            _error = null;
            _typed.clear();
          }),
          child: const Text(RecoveryKeyCopy.savedIt),
        ),
      ],
    );
  }

  Widget _confirmStep(List<String> groups) {
    final ThemeData theme = Theme.of(context);
    final int last = groups.length;
    return CardPage(
      title: RecoveryKeyCopy.confirmTitle,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, DialSpace.xs, 6, DialSpace.l),
          child: Text(
            RecoveryKeyCopy.confirmPrompt(last),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DialColors.of(context).muted,
            ),
          ),
        ),
        TextField(
          key: RecoveryKeyPage.confirmField,
          controller: _typed,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            fontFamily: DialFonts.mono,
            fontFeatures: DialFonts.tabular,
            fontSize: 22,
            letterSpacing: 3,
          ),
          decoration: InputDecoration(
            labelText: RecoveryKeyCopy.confirmLabel(last),
            errorText: _error,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
          onSubmitted: (_) => _confirm(groups),
        ),
        const SizedBox(height: DialSpace.xl),
        FilledButton(
          onPressed: () => _confirm(groups),
          child: const Text(RecoveryKeyCopy.confirm),
        ),
        const SizedBox(height: DialSpace.xs),
        TextButton(
          onPressed: () => setState(() => _confirming = false),
          child: const Text(RecoveryKeyCopy.showAgain),
        ),
      ],
    );
  }
}

/// The message for text that is not this journal's recovery key, or null
/// when [parse] is a well-formed key.
String? recoveryKeyProblem(RecoveryKeyParse parse) => switch (parse) {
  RecoveryKeyOk() => null,
  RecoveryKeyBadCharacter(:final String character, :final int position) =>
    RecoveryKeyCopy.badCharacter(character, position),
  RecoveryKeyWrongLength(:final int length) => RecoveryKeyCopy.wrongLength(
    length,
  ),
  RecoveryKeyTypo(:final int? position, :final int? group) =>
    position == null
        ? RecoveryKeyCopy.typo
        : RecoveryKeyCopy.typoAt(
            (position - 1) % RecoveryKey.groupSize + 1,
            group!,
          ),
};

/// Asks for the recovery key on a device that has no journal key.
class RecoveryKeyEntryPage extends ConsumerStatefulWidget {
  const RecoveryKeyEntryPage({super.key});

  static const Key field = Key('recovery-entry-field');

  @override
  ConsumerState<RecoveryKeyEntryPage> createState() =>
      _RecoveryKeyEntryPageState();
}

class _RecoveryKeyEntryPageState extends ConsumerState<RecoveryKeyEntryPage> {
  final TextEditingController _typed = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final RecoveryKeyParse parse = RecoveryKey.parse(_typed.text);
    final String? problem = recoveryKeyProblem(parse);
    if (problem != null || parse is! RecoveryKeyOk) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _busy = true);
    final UnlockOutcome outcome = await ref
        .read(recoveryKeyActionsProvider)
        .unlock(parse.key);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (outcome) {
        UnlockOpened() => null,
        UnlockNotThisJournal() => RecoveryKeyCopy.notThisJournal,
        UnlockFailed(:final String message) => message,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return CardPage(
      title: RecoveryKeyCopy.entryTitle,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, DialSpace.xs, 6, DialSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                RecoveryKeyCopy.entryHeading,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                RecoveryKeyCopy.entryBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DialColors.of(context).muted,
                ),
              ),
            ],
          ),
        ),
        TextField(
          key: RecoveryKeyEntryPage.field,
          controller: _typed,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 2,
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
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
        ),
        const SizedBox(height: DialSpace.xl),
        FilledButton(
          onPressed: _busy ? null : _unlock,
          child: const Text(RecoveryKeyCopy.unlock),
        ),
      ],
    );
  }
}

/// Holds [child] closed behind [RecoveryKeyEntryPage] while the journal
/// needs its recovery key on this device.
class RecoveryKeyGate extends ConsumerWidget {
  const RecoveryKeyGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(journalNeedsRecoveryKeyProvider)
      ? const RecoveryKeyEntryPage()
      : child;
}
