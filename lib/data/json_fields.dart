import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/limits.dart';

// Firestore documents are untyped, and legacy ones predate the rules that now
// fix field types, so every read falls back to a value instead of throwing.

String readString(Object? value) => value is String ? value : '';

bool readBool(Object? value, {required bool fallback}) =>
    value is bool ? value : fallback;

int readInt(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite) return value.round();
  if (value is String) {
    final num? parsed = num.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) return parsed.round();
  }
  return 0;
}

// An activity's optional decimal amount: null when missing, mistyped or not
// above zero, so the caller falls back to the whole-number quantity.
double? readAmount(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toDouble() : null;

final Timestamp epoch = Timestamp(0, 0);

/// [pending] is true for a latency-compensated local snapshot, where an
/// unresolved `FieldValue.serverTimestamp()` reads as null and the server will
/// fill in roughly the current time.
Timestamp readTimestamp(Object? value, {required bool pending}) {
  if (value is Timestamp) return value;
  if (value is DateTime) return Timestamp.fromDate(value);
  return pending ? Timestamp.now() : epoch;
}

// A habit's own unit label: null when missing, mistyped, blank or past
// [maxUnitLabelLength], so the preset's words show instead.
String? readUnitLabel(Object? value) {
  if (value is! String) return null;
  final String label = value.trim();
  return label.isEmpty || label.length > maxUnitLabelLength ? null : label;
}

double? readCostPerUnit(Object? value) =>
    value is num && value.isFinite && value > 0 && value <= maxCostPerUnit
    ? value.toDouble()
    : null;

String? readCurrency(Object? value) =>
    value is String && currencyCodePattern.hasMatch(value) ? value : null;
