import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/insights/experiment.dart';

/// The experiments, sealed under Application Support: a plan of several
/// weeks must not vanish when iOS empties Caches.
class ExperimentFile {
  ExperimentFile(this._files);

  final SealedFiles _files;

  static const String name = 'experiment';

  String get uid => _files.uid;

  /// [ExperimentStore.empty] when absent or unreadable.
  Future<ExperimentStore> load() async => switch (await _files.read(name)) {
    final List<int> bytes => ExperimentStore.decode(bytes),
    null => ExperimentStore.empty,
  };

  Future<void> save(ExperimentStore store) =>
      store.active == null && store.finished.isEmpty
      ? _files.delete(name)
      : _files.write(name, store.encode());
}
