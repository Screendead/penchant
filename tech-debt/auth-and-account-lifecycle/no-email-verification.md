# Registration never sends a verification email and no rule checks emailVerified

**Severity:** medium

`createUserWithEmailAndPassword` in `register.dart` is not followed by
`sendEmailVerification`, so accounts are created and immediately usable with
an unverified address. `firestore.rules` tests only the auth uid and never
the token's `email_verified` claim, so nothing in the read or write gate
depends on the address having been proven to belong to the registrant.

## Evidence

- **`grep -rn "sendEmailVerification\|emailVerified" lib/`** → `(no matches)`
- `lib/register.dart:170` — `await FirebaseAuth.instance
                              .createUserWithEmailAndPassword(
                            email: emailController.text,
                            password: passwordController.text,
                          );`
- `firestore.rules:7` — `allow read, write: if request.auth.uid != null && request.auth.uid == resource.data.ownerID;`
