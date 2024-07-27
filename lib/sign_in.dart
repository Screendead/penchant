import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  GlobalKey<FormState> formKey = GlobalKey<FormState>();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();
  bool? emailIsValid;
  String? error;

  bool get isValid => emailIsValid ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In to Your Account'),
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
                  prefixIcon: const Icon(Icons.email),
                  suffixIcon: emailIsValid == null
                      ? null
                      : Tooltip(
                          message: emailIsValid!
                              ? 'Email is valid'
                              : 'Please enter a valid email address',
                          child: Icon(
                            emailIsValid! ? Icons.check_circle : Icons.cancel,
                            color: emailIsValid! ? Colors.green : Colors.red,
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
                    return 'Please enter your email address';
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
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isValid
                    ? () async {
                        if (formKey.currentState!.validate()) {
                          try {
                            await FirebaseAuth.instance
                                .signInWithEmailAndPassword(
                              email: emailController.text,
                              password: passwordController.text,
                            );
                          } on FirebaseAuthException catch (e) {
                            setState(() {
                              error = e.message;
                            });
                          }
                        } else {
                          setState(() {
                            error = null;
                          });
                        }
                      }
                    : null,
                child: const Text('Sign In'),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
      ),
    );
  }
}
