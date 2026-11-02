# Nothing in the app calls sendPasswordResetEmail

**Severity:** high

`sign_in.dart`'s form has exactly one action, the Sign In button; there is no
forgot-password link, route, or screen anywhere in `lib/`. A user who forgets
their password has no in-app recovery path and no way back to the account or
its Firestore data.

## Evidence

- **`grep -rn "sendPasswordResetEmail" lib/`** → `(no matches)`
- `lib/sign_in.dart:93` — `ElevatedButton(
                onPressed: isValid
                    ? () async {
                        if (formKey.currentState!.validate()) {`
