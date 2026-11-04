# Nothing depends on a verified address

**Severity:** medium

Registration sends a verification email and Account Settings shows whether the address is verified, but an
unverified account is fully usable: no screen waits for verification, and `firestore.rules` tests only the auth uid,
never the token's `email_verified` claim. An address nobody has proven to own can hold an account, and the password
reset link for it goes to whoever does own it. Every account created before verification was sent is unverified, so
gating on the claim would lock all of them out until they verify.

## Evidence

- **`grep -n "email_verified" firestore.rules`** → `(no matches)`
- `lib/account/account.dart` — `register` sends the email and returns; nothing reads `emailVerified` except the
  status row in `lib/account_settings.dart`.
- `firestore.rules:5-7` — `function signedIn() {\n      return request.auth != null;\n    }`
