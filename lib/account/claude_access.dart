import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this account may use Claude: an email address verified, never a
/// guest. The server refuses everyone else (`verifiedCaller`,
/// functions/caller.js), so every Claude provider is null without it.
final claudeAllowedProvider = Provider<bool>((Ref ref) {
  final bool verified = ref.watch(
    userProfileProvider.select(
      (AsyncValue<User?> user) => user.value?.emailVerified ?? false,
    ),
  );
  // Linking leaves a User anonymous; Account reads the live one.
  return verified && !ref.read(accountProvider).isGuest;
});

const String claudeNeedsEmail = 'Add and verify an email address first.';

/// Calls the Cloud Function [name] with [data]. A `permission-denied` answer
/// may come from an ID token minted before the email was verified, whose
/// `email_verified` claim stays false until it refreshes, so the token is
/// refreshed once and the call made again.
Future<Object?> callClaude(
  String name,
  Duration timeout,
  Map<String, Object?> data,
) async {
  final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: timeout),
  );
  try {
    return (await callable.call<Object?>(data)).data;
  } on FirebaseFunctionsException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    return (await callable.call<Object?>(data)).data;
  }
}

/// A Claude switch's row while [claudeAllowedProvider] is false: off, the
/// switch disabled, and a tap opening Account Settings to add and verify an
/// email.
class ClaudeNeedsEmailRow extends StatelessWidget {
  const ClaudeNeedsEmailRow({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: CardRow(
      label: label,
      subtitle: claudeNeedsEmail,
      onTap: () => Navigator.of(context).pushNamed('/settings/account'),
      trailing: const Switch.adaptive(value: false, onChanged: null),
    ),
  );
}
