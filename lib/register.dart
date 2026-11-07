import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/account/email.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/widgets/auth_parts.dart';

class Register extends ConsumerStatefulWidget {
  const Register({super.key});

  @override
  ConsumerState<Register> createState() => _RegisterState();
}

class _RegisterState extends ConsumerState<Register> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool? emailIsValid;
  Map<String, bool> checks = PasswordRules.check('', '');
  bool busy = false;
  String? error;

  bool get isValid =>
      (emailIsValid ?? false) && checks.values.every((bool ok) => ok) && !busy;

  void _recheck() {
    setState(() {
      checks = PasswordRules.check(
        passwordController.text,
        confirmPasswordController.text,
      );
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
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
          .register(
            email: emailController.text.trim(),
            password: passwordController.text,
          );
    } catch (e, stack) {
      reportError(e, stack, context: 'while registering');
      if (mounted) {
        setState(() => error = authErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
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
              autofillHints: const <String>[AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              onChanged: (_) => _recheck(),
            ),
            const SizedBox(height: 10),
            AuthField(
              controller: confirmPasswordController,
              hint: 'Confirm password',
              glyph: DialGlyph.lock,
              obscurable: true,
              autofillHints: const <String>[AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onChanged: (_) => _recheck(),
              onSubmitted: (_) {
                if (isValid) {
                  _register();
                }
              },
            ),
            PasswordChecklist(checks: checks),
            if (error != null) AuthErrorPill(error!),
            AuthPrimaryButton(
              label: 'Create account',
              busy: busy,
              onPressed: isValid ? _register : null,
            ),
          ],
        ),
      ),
    );
  }
}
