import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/account/email.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/account/password_prompt.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/settings_card.dart';

class AccountSettings extends ConsumerWidget {
  const AccountSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> userValue = ref.watch(userProfileProvider);
    final User? user = userValue.value;
    return CardPage(
      title: 'Account Settings',
      children: <Widget>[
        switch ((user, userValue.error)) {
          (final User user, _) => _AccountSettingsBody(
            key: ValueKey<String>(user.uid),
            user: user,
          ),
          (null, final Object _) => ErrorView(
            message: AccountCopy.profileLoadFailed,
            onRetry: () => ref.invalidate(userProfileProvider, asReload: true),
          ),
          (null, null) => const Padding(
            padding: EdgeInsets.only(top: DialSpace.xxxl),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

class _AccountSettingsBody extends ConsumerStatefulWidget {
  const _AccountSettingsBody({super.key, required this.user});

  final User user;

  @override
  ConsumerState<_AccountSettingsBody> createState() =>
      _AccountSettingsBodyState();
}

class _AccountSettingsBodyState extends ConsumerState<_AccountSettingsBody> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _exportTile = GlobalKey();
  late final TextEditingController _displayName = TextEditingController(
    text: widget.user.displayName,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.user.email,
  );
  late final TextEditingController _photoURL = TextEditingController(
    text: widget.user.photoURL,
  );
  late final AppLifecycleListener _lifecycle;
  String? _busy;

  // A verification link is usually opened outside the app, so the address's
  // status is fetched on opening and again on returning to the app.
  @override
  void initState() {
    super.initState();
    _account.reloadUser();
    _lifecycle = AppLifecycleListener(onResume: _account.reloadUser);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _displayName.dispose();
    _email.dispose();
    _photoURL.dispose();
    super.dispose();
  }

  Account get _account => ref.read(accountProvider);

  String? _blankToNull(String text) => text.trim().isEmpty ? null : text.trim();

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // Runs [action] with the screen locked behind [label], so a second tap
  // cannot start a second copy of it.
  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy != null) {
      return;
    }
    setState(() => _busy = label);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = null);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final User user = widget.user;
    final String? displayName = _blankToNull(_displayName.text);
    final String? photoURL = _blankToNull(_photoURL.text);
    final String email = _email.text.trim();
    final bool emailChanged = email != user.email;

    String? password;
    if (emailChanged) {
      password = await promptForPassword(
        context,
        message: AccountCopy.emailChangePasswordPrompt(user.email ?? ''),
        action: 'Change email',
      );
      if (password == null) {
        return;
      }
    }

    await _run('Saving…', () async {
      final List<String> done = <String>[];
      try {
        if (displayName != _blankToNull(user.displayName ?? '')) {
          await _account.updateDisplayName(displayName);
          done.add('Display name saved.');
        }
        if (photoURL != user.photoURL) {
          await _account.updatePhotoURL(photoURL);
          done.add('Photo URL saved.');
        }
        if (emailChanged) {
          await _account.changeEmail(email, password: password!);
          // user.email changes only once the link is followed; until then a
          // field still holding the new address would re-send on every save.
          _email.text = user.email ?? '';
          done.add(AccountCopy.emailChangeSent(email));
        }
        _show(done.isEmpty ? 'Nothing to save.' : done.join(' '));
      } catch (e, stack) {
        reportError(e, stack, context: 'while saving the profile');
        _show(<String>[...done, 'Not saved: ${authErrorMessage(e)}'].join(' '));
      }
    });
  }

  Future<void> _resendVerification() => _run('Sending…', () async {
    try {
      await _account.sendEmailVerification();
      _show(AccountCopy.verificationSent(widget.user.email ?? ''));
    } catch (e, stack) {
      reportError(e, stack, context: 'while sending a verification email');
      _show(authErrorMessage(e));
    }
  });

  Rect? _exportOrigin() {
    final RenderObject? box = _exportTile.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // The origin is read before the busy view replaces the tile; the iPad share
  // sheet needs it as its anchor.
  Future<void> _export() {
    final Rect? origin = _exportOrigin();
    return _run('Preparing your export…', () async {
      try {
        final AccountData data = await _account.fetchData();
        await ref
            .read(exportShareProvider)
            .share(exportFiles(data, DateTime.now()), origin: origin);
      } catch (e, stack) {
        reportError(e, stack, context: 'while exporting account data');
        _show(AccountCopy.exportFailed(authErrorMessage(e)));
      }
    });
  }

  Future<void> _delete() async {
    final _DeleteChoice? choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (BuildContext context) => const _DeleteConfirmation(),
    );
    if (!mounted) {
      return;
    }
    if (choice == _DeleteChoice.exportFirst) {
      await _export();
      return;
    }
    if (choice != _DeleteChoice.proceed) {
      return;
    }
    final String? password = await promptForPassword(
      context,
      message: AccountCopy.deletePasswordPrompt(widget.user.email ?? ''),
      action: AccountCopy.deleteConfirmAction,
    );
    if (password == null || !mounted) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await _run(AccountCopy.deleting, () async {
      try {
        await _account.deleteAccount(password: password);
      } on DeletionIncompleteException catch (e, stack) {
        reportError(e.cause, stack, context: 'while deleting the account');
        _show(AccountCopy.deleteIncomplete(authErrorMessage(e.cause)));
        return;
      } catch (e, stack) {
        reportError(e, stack, context: 'while deleting the account');
        _show(AccountCopy.deleteFailed(authErrorMessage(e)));
        return;
      }
      navigator.popUntil((Route<dynamic> route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(content: Text(AccountCopy.deleted)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? busy = _busy;
    if (busy != null) {
      return Padding(
        padding: const EdgeInsets.only(top: DialSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(busy),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const CardSectionLabel('Profile'),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: DialSpace.m),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (String? value) => emailError(value?.trim()),
              ),
              const SizedBox(height: DialSpace.m),
              TextFormField(
                controller: _photoURL,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Photo URL'),
              ),
              const SizedBox(height: DialSpace.m),
              ElevatedButton(
                onPressed: _saveProfile,
                child: const Text('Update Profile'),
              ),
            ],
          ),
        ),
        DialCard(
          top: DialSpace.xl,
          children: <Widget>[
            CardRow(
              label: widget.user.emailVerified
                  ? AccountCopy.verified
                  : AccountCopy.notVerified,
              trailing: widget.user.emailVerified
                  ? null
                  : TextButton(
                      onPressed: _resendVerification,
                      child: const Text(AccountCopy.resendVerification),
                    ),
            ),
          ],
        ),
        const CardSectionLabel(AccountCopy.dataSection),
        DialCard(
          top: 0,
          children: <Widget>[
            CardRow(
              label: RecoveryKeyCopy.settingsRow,
              subtitle: RecoveryKeyCopy.settingsSubtitle,
              glyph: DialGlyph.right,
              onTap: () =>
                  Navigator.of(context).pushNamed(RecoveryKeyPage.route),
            ),
            CardRow(
              key: _exportTile,
              label: AccountCopy.exportTitle,
              subtitle: AccountCopy.exportSubtitle,
              glyph: DialGlyph.share,
              onTap: _export,
            ),
            CardRow(
              label: AccountCopy.deleteTitle,
              subtitle: AccountCopy.deleteSubtitle,
              danger: true,
              onTap: _delete,
            ),
          ],
        ),
      ],
    );
  }
}

enum _DeleteChoice { exportFirst, proceed }

class _DeleteConfirmation extends StatelessWidget {
  const _DeleteConfirmation();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AccountCopy.deleteConfirmTitle),
      content: const Text(AccountCopy.deleteConfirmBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AccountCopy.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.exportFirst),
          child: const Text(AccountCopy.deleteConfirmExportFirst),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.proceed),
          child: const Text(AccountCopy.deleteConfirmContinue),
        ),
      ],
    );
  }
}
