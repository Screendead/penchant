import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/notes/note_search.dart';
import 'package:tracker/providers/user_provider.dart';

// Search by meaning: Apple's on-device sentence embedding
// (ios/Runner/SentenceEmbeddingChannel.swift, compiled into both Runners).
// Nothing is sent anywhere, and the vectors are held in memory only, for the
// signed-in session.

/// Turns text into vectors on the device.
abstract interface class SentenceEmbedder {
  /// Whether this device has a sentence embedding for its language.
  Future<bool> available();

  /// One vector per text, null where the model gives none.
  Future<List<Float32List?>> embed(List<String> texts);
}

class ChannelSentenceEmbedder implements SentenceEmbedder {
  const ChannelSentenceEmbedder();

  static const MethodChannel _channel = MethodChannel(
    'com.screendead.penchant/sentence_embedding',
  );

  @override
  Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<Float32List?>> embed(List<String> texts) async {
    final List<Object?>? vectors = await _channel.invokeListMethod<Object?>(
      'embed',
      texts,
    );
    if (vectors == null || vectors.length != texts.length) {
      throw StateError(
        'embedding answered ${vectors?.length} of '
        '${texts.length}',
      );
    }
    return <Float32List?>[
      for (final Object? v in vectors) v is Float32List ? v : null,
    ];
  }
}

final sentenceEmbedderProvider = Provider<SentenceEmbedder>(
  (ref) => const ChannelSentenceEmbedder(),
);

/// Whether this device can search by meaning: false off Apple platforms, on
/// an OS or in a language without a sentence embedding.
final meaningAvailableProvider = FutureProvider<bool>((ref) {
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS) {
    return false;
  }
  return ref.watch(sentenceEmbedderProvider).available();
});

/// Each note's vector, made lazily on the first search by meaning and kept
/// for the session: a new user starts an empty one.
final meaningIndexProvider = Provider<MeaningIndex>((ref) {
  ref.watch(userProvider.select((u) => u.value?.uid));
  return MeaningIndex(ref.watch(sentenceEmbedderProvider));
});

class MeaningIndex {
  MeaningIndex(this._embedder);

  final SentenceEmbedder _embedder;

  // Keyed on the note and its text, so an edited note is embedded again.
  final Map<String, Float32List?> _vectors = <String, Float32List?>{};

  static const int batchSize = 64;

  static String _key(SearchableNote n) => '${n.key}\u0000${n.text}';

  /// Each note's cosine similarity with [query], by note key; empty if the
  /// query has no vector.
  Future<Map<String, double>> similarities(
    String query,
    List<SearchableNote> notes,
  ) async {
    final List<SearchableNote> missing = <SearchableNote>[
      for (final SearchableNote n in notes)
        if (!_vectors.containsKey(_key(n))) n,
    ];
    for (int i = 0; i < missing.length; i += batchSize) {
      final List<SearchableNote> batch = missing.sublist(
        i,
        (i + batchSize).clamp(0, missing.length),
      );
      final List<Float32List?> vectors = await _embedder.embed(<String>[
        for (final SearchableNote n in batch) n.text,
      ]);
      for (int k = 0; k < batch.length; k++) {
        _vectors[_key(batch[k])] = vectors[k];
      }
    }
    final Float32List? q = (await _embedder.embed(<String>[query])).single;
    if (q == null) return const <String, double>{};
    return <String, double>{
      for (final SearchableNote n in notes)
        if (_vectors[_key(n)] case final Float32List v)
          n.key: cosineSimilarity(q, v),
    };
  }
}

/// Whether search also looks for notes close in meaning: off until turned
/// on, per device. Off by default because on the trial's made-up notes it
/// found little that word search missed (tools/note-search-trial.swift).
final meaningSearchProvider = NotifierProvider<MeaningSearch, bool>(
  MeaningSearch.new,
);

class MeaningSearch extends Notifier<bool> {
  static const String key = 'noteSearchMeaning';

  bool _chosen = false;

  @override
  bool build() {
    _load();
    return false;
  }

  // A failed read leaves it off.
  Future<void> _load() async {
    final bool? saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = prefs.getBool(key);
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the meaning search choice');
      return;
    }
    if (saved != null && !_chosen) {
      state = saved;
    }
  }

  Future<void> choose(bool on) async {
    _chosen = true;
    state = on;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, on);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the meaning search choice');
    }
  }
}
