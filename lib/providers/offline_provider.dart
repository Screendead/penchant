import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/providers/user_provider.dart';

// Every launch with a warm cache answers from it first, for about as long as
// the server takes to reply; calling that offline would cry wolf.
const Duration offlineDelay = Duration(seconds: 3);

/// Emits false at once, and true only once [fromCache] has stayed true for
/// [delay].
Stream<bool> sustainedOffline(Stream<bool> fromCache, Duration delay) {
  Timer? timer;
  StreamSubscription<bool>? subscription;
  late final StreamController<bool> controller;

  controller = StreamController<bool>(
    onListen: () {
      subscription = fromCache.listen(
        (bool cached) {
          timer?.cancel();
          if (cached) {
            timer = Timer(delay, () => controller.add(true));
          } else {
            controller.add(false);
          }
        },
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      timer?.cancel();
      return subscription?.cancel();
    },
  );

  return controller.stream.distinct();
}

// True while Firestore has been answering from the device's cache, which it
// does when it cannot reach the backend, including after disableNetwork().
final offlineProvider = StreamProvider<bool>((ref) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<bool>.empty();
  }

  // The same query as viceListProvider, so the SDK serves both from one
  // listen. Going offline changes only metadata, which raises an event only
  // with includeMetadataChanges.
  return sustainedOffline(
    FirebaseFirestore.instance
        .collection('vices')
        .where('ownerID', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) =>
              snapshot.metadata.isFromCache,
        ),
    offlineDelay,
  );
});
