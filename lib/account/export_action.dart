import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';

/// Where [key]'s widget sits on screen, for anchoring the iPad share sheet.
/// Read it before anything replaces that widget.
Rect? exportOrigin(GlobalKey key) {
  final RenderObject? box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return null;
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Fetches the signed-in user's journal and hands the CSV and JSON to the
/// share sheet. Returns the message to show when that fails, or null.
Future<String?> shareAccountExport(WidgetRef ref, {Rect? origin}) async {
  try {
    final AccountData data = await ref.read(accountProvider).fetchData();
    await ref
        .read(exportShareProvider)
        .share(exportFiles(data, DateTime.now()), origin: origin);
    return null;
  } catch (e, stack) {
    reportError(e, stack, context: 'while exporting account data');
    return AccountCopy.exportFailed(authErrorMessage(e));
  }
}
