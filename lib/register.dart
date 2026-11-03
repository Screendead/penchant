import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  GlobalKey<FormState> formKey = GlobalKey<FormState>();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();
  bool? emailIsValid;
  bool? passwordIsValid;
  bool? passwordsMatch;
  String? error;

  bool get isValid =>
      (emailIsValid ?? false) &&
      (passwordIsValid ?? false) &&
      (passwordsMatch ?? false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register a New Account'),
      ),
      body: Form(
        key: formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'john.doe@example.com',
                  prefixIcon: const Icon(Icons.email),
                  suffixIcon: emailIsValid == null
                      ? null
                      : Tooltip(
                          message: emailIsValid!
                              ? 'Email is valid'
                              : 'Please enter a valid email address',
                          child: Icon(
                            emailIsValid! ? Icons.check_circle : Icons.cancel,
                            color: emailIsValid!
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                ),
                onChanged: (String value) {
                  if (value == '') {
                    setState(() {
                      emailIsValid = null;
                    });
                  } else {
                    setState(() {
                      emailIsValid = emailRegex.hasMatch(value);
                    });
                  }
                },
                validator: (String? value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an email address';
                  }
                  if (!emailRegex.hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: passwordIsValid == null
                      ? null
                      : Tooltip(
                          message: passwordIsValid!
                              ? 'Password is valid'
                              : 'Password must be at least 8 characters long '
                                  'and contain at least one uppercase letter, '
                                  'one lowercase letter, and one number',
                          child: Icon(
                            passwordIsValid!
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: passwordIsValid!
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                ),
                onChanged: (String value) {
                  setState(() {
                    passwordIsValid = value.length >= 8 &&
                        value.contains(RegExp(r'[A-Z]')) &&
                        value.contains(RegExp(r'[a-z]')) &&
                        value.contains(RegExp(r'[0-9]'));
                    passwordsMatch = confirmPasswordController.text == value;
                  });
                },
                validator: (String? value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 8) {
                    return 'Password must be at least 8 characters long';
                  }
                  if (!value.contains(RegExp(r'[A-Z]'))) {
                    return 'Password must contain at least one uppercase letter';
                  }
                  if (!value.contains(RegExp(r'[a-z]'))) {
                    return 'Password must contain at least one lowercase letter';
                  }
                  if (!value.contains(RegExp(r'[0-9]'))) {
                    return 'Password must contain at least one number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_reset),
                  suffixIcon: passwordsMatch == null
                      ? null
                      : Tooltip(
                          message: passwordsMatch!
                              ? 'Passwords match'
                              : 'Passwords do not match',
                          child: Icon(
                            passwordsMatch! ? Icons.check_circle : Icons.cancel,
                            color: passwordsMatch!
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                ),
                onChanged: (String value) {
                  setState(() {
                    passwordsMatch = value == passwordController.text;
                  });
                },
                validator: (String? value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isValid
                    ? () async {
                        if (formKey.currentState!.validate()) {
                          await FirebaseAuth.instance
                              .createUserWithEmailAndPassword(
                            email: emailController.text,
                            password: passwordController.text,
                          );
                        } else {
                          setState(() {
                            error = null;
                          });
                        }
                      }
                    : null,
                child: const Text('Register'),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
      ),
    );
  }
}
