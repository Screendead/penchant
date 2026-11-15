import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A starter-tree trigger [path] a note supports, with the words of the note
/// that support it ([quote], copied from the note exactly).
typedef ReadTag = ({String path, String quote});

/// Reads a free-text note into triggers for the person to confirm.
abstract class NoteReader {
  /// Each tag as it is found, closing once the note is read. An error means
  /// the rest could not be read; callers then ask for tags by hand. A tag
  /// whose path is not in the tree or whose quote is not in [note] is never
  /// emitted.
  Stream<ReadTag> read(String note);
}

/// Null while reading notes is switched off or cannot work here (signed out,
/// offline, an emulator build): tags are then picked by hand.
final Provider<NoteReader?> noteReaderProvider = Provider<NoteReader?>(
  (Ref ref) => null,
);
