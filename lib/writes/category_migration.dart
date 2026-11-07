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
// a category guessed from its name. The vice list the screens already listen
// to picks the candidates; each write is a transaction that checks the
// server's copy first, since the first snapshot of a launch comes from the
// cache, which on a second device can predate a category chosen elsewhere.
// Offline the transaction fails and a later snapshot or launch tries again.
// [_issued] keeps a vice to one attempt at a time, and a refusal to one per
// launch.
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
      unawaited(_fill(vice));
    }
  }

  Future<void> _fill(Vice vice) async {
    try {
      await ref
          .read(trackerWritesProvider)
          .fillViceCategory(vice.id, guessCategory(vice.name));
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        _issued.remove(vice.id);
      } else {
        reportError(e, e.stackTrace, context: 'while adding a category');
      }
    } catch (e, stack) {
      reportError(e, stack, context: 'while adding a category');
    }
  }
}

final categoryMigrationProvider = NotifierProvider<CategoryMigration, void>(
  CategoryMigration.new,
);
