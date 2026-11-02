# sign_in.dart displays FirebaseAuthException.message unmodified

**Severity:** medium

The catch block stores and renders the message with no mapping. If the
Firebase project has email-enumeration protection disabled, a project-level
setting not visible from the repository, `user-not-found` and
`wrong-password` produce distinct default messages, letting a caller learn
whether a given address has a registered account. No code-level mapping
exists that would prevent that regardless of the project setting.

## Evidence

- `lib/sign_in.dart:103` — `} on FirebaseAuthException catch (e) {
                            setState(() {
                              error = e.message;
                            });
                          }`
- `lib/sign_in.dart:117` — `if (error != null) Text(error!),`
