import 'package:flutter/material.dart';
import 'package:tracker/account/account_copy.dart';

// Asks for the current password before an action Firebase guards with a
// recent sign-in. Null means the user cancelled.
Future<String?> promptForPassword(
  BuildContext context, {
  required String message,
  required String action,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) =>
        _PasswordPrompt(message: message, action: action),
  );
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({required this.message, required this.action});

  final String message;
  final String action;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isNotEmpty) {
      Navigator.of(context).pop(_password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AccountCopy.passwordPromptTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: AccountCopy.password),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AccountCopy.cancel),
        ),
        TextButton(
          onPressed: _password.text.isEmpty ? null : _submit,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
