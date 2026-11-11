import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/insights/health_sample_cache.dart';
import 'package:tracker/providers/insights_session.dart';

final deviceFilesProvider = Provider<DeviceFiles>((ref) => DeviceFiles());

/// The journal key's file sealer; null while no key is loaded.
final fileSealerProvider = Provider<FileSealer?>(
  (ref) => switch (ref.watch(sealerProvider)) {
    final FileSealer sealer => sealer,
    _ => null,
  },
);

/// The signed-in user's sealed device files; null while nobody is signed in
/// or no key is loaded, when nothing is read or written.
final sealedFilesProvider = Provider<SealedFiles?>((ref) {
  final String? uid = ref.watch(insightsUidProvider);
  final FileSealer? sealer = ref.watch(fileSealerProvider);
  if (uid == null || sealer == null) return null;
  return ref.watch(deviceFilesProvider).forUser(uid, sealer);
});

final healthSampleCacheProvider = Provider<HealthSampleCache?>((ref) {
  final SealedFiles? files = ref.watch(sealedFilesProvider);
  return files == null ? null : HealthSampleCache(files);
});
