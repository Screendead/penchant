import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// Filtered here, not by the query: `where('archived', isEqualTo: false)`
// matches only documents that hold the field, and vices written before it
// existed lack it.
final unarchivedViceListProvider = Provider.autoDispose<AsyncValue<List<Vice>>>(
  (ref) {
    return ref
        .watch(viceListProvider)
        .whenData(
          (List<Vice> vices) => <Vice>[
            for (final Vice vice in vices)
              if (!vice.archived) vice,
          ],
        );
  },
);
