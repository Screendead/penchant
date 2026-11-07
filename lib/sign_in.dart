import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/account/email.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/widgets/auth_parts.dart';

class SignIn extends ConsumerStatefulWidget {
  const SignIn({super.key});

  @override
  ConsumerState<SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<SignIn> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool passwordIsObscured = true;
  bool? emailIsValid;
  bool hasPassword = false;
  bool busy = false;
  String? error;

  bool get isValid => (emailIsValid ?? false) && hasPassword && !busy;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!formKey.currentState!.validate()) {
      setState(() => error = null);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(accountProvider)
          .signIn(
            email: emailController.text.trim(),
            password: passwordController.text,
          );
      TextInput.finishAutofillContext();
    } catch (e, stack) {
      reportError(e, stack, context: 'while signing in');
      if (mounted) {
        setState(() => error = authErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final String? email = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          ResetPasswordDialog(initialEmail: emailController.text.trim()),
    );
    if (email == null || !mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    String message = AccountCopy.resetSent(email);
    try {
      await ref.read(accountProvider).sendPasswordResetEmail(email);
    } catch (e, stack) {
      reportError(e, stack, context: 'while sending a password reset email');
      // Whether the address has an account is not the screen's to say.
      if (!(e is FirebaseAuthException && e.code == 'user-not-found')) {
        message = authErrorMessage(e);
      }
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthField(
              controller: emailController,
              hint: 'Email',
              glyph: DialGlyph.mail,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              onChanged: (String value) {
                setState(() {
                  emailIsValid = value.isEmpty
                      ? null
                      : emailPattern.hasMatch(value.trim());
                });
              },
              validator: (String? value) => emailError(value?.trim()),
            ),
            const SizedBox(height: 10),
            AuthField(
              controller: passwordController,
              hint: 'Password',
              glyph: DialGlyph.lock,
              obscurable: true,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              onChanged: (String value) {
                setState(() => hasPassword = value.isNotEmpty);
              },
              onSubmitted: (_) {
                if (isValid) {
                  _signIn();
                }
              },
            ),
            if (error != null) AuthErrorPill(error!),
            AuthPrimaryButton(
              label: 'Sign in',
              busy: busy,
              onPressed: isValid ? _signIn : null,
            ),
            const SizedBox(height: DialSpace.xs),
            Center(
              child: TextButton(
                onPressed: busy ? null : _resetPassword,
                child: const Text(
                  AccountCopy.forgotPassword,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Pops with the address to send the link to, or null if cancelled.
class ResetPasswordDialog extends StatefulWidget {
  const ResetPasswordDialog({super.key, required this.initialEmail});

  final String initialEmail;

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_email.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AccountCopy.resetTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(AccountCopy.resetBody),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (String? value) => emailError(value?.trim()),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AccountCopy.cancel),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(AccountCopy.resetSend),
        ),
      ],
    );
  }
}
