import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// Gives each of the signed-in user's vices written before `category` existed
// a category guessed from its name. It reads the vice list the screens already
// listen to, so it costs no reads and works from the cache offline, where the
// writes queue. A queued write shows on the local snapshot at once, so a vice
// is written once; [_issued] covers the moment before that snapshot, and a
// refusal, which would otherwise be retried on every snapshot.
class CategoryMigration extends Notifier<void> {
  final Set<String> _issued = <String>{};

  @override
  void build() {
    ref.listen<String?>(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
      (_, _) => _issued.clear(),
    );
    ref.listen<AsyncValue<List<Vice>>>(
      viceListProvider,
      (_, AsyncValue<List<Vice>> next) => _migrate(next.value),
      fireImmediately: true,
    );
  }

  void _migrate(List<Vice>? vices) {
    if (vices == null) {
      return;
    }
    for (final Vice vice in vices) {
      if (vice.categoryStored || !_issued.add(vice.id)) {
        continue;
      }
      try {
        unawaited(
          ref
              .read(trackerWritesProvider)
              .updateVice(vice.id, category: guessCategory(vice.name))
              .done
              .catchError((Object e, StackTrace stack) {
                reportError(e, stack, context: 'while adding a category');
              }),
        );
      } catch (e, stack) {
        reportError(e, stack, context: 'while adding a category');
      }
    }
  }
}

final categoryMigrationProvider = NotifierProvider<CategoryMigration, void>(
  CategoryMigration.new,
);
