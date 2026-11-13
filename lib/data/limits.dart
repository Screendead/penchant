import 'package:tracker/formats.dart';

// Mirrors firestore.rules, so a form refuses what the rules would deny.

// Counted in UTF-16 code units (String.length), as the rules' size() is.
const int maxViceNameLength = 60;

// The rules check the name only when an update changes it, so a legacy vice's
// out-of-range name can be saved back as it is.
String? viceNameError(String? value, {String? unchanged}) {
  if (value != null && value == unchanged) {
    return null;
  }

  if (value == null || value.isEmpty) {
    return 'Please enter a name';
  }

  if (value.length > maxViceNameLength) {
    return 'Use $maxViceNameLength characters or fewer';
  }

  return null;
}

// The rules check quantity and amount only when an update changes them, so a
// legacy activity's out-of-range value can be saved back as it is.
String? quantityError(String? value, {num? unchanged}) {
  if (value == null || value.trim().isEmpty) {
    return 'Please enter a quantity';
  }

  final num? quantity = parseAmount(value);

  if (quantity == null) {
    return 'Please enter a valid number';
  }

  if (quantity <= 0 && quantity != unchanged) {
    return 'Please enter more than 0';
  }

  return null;
}

// An activity's triggers: at most [maxTriggers] entries, each 1 to
// [maxTriggerLength] UTF-16 code units.
const int maxTriggers = 10;
const int maxTriggerLength = 60;

String? triggersError(List<String> triggers) {
  if (triggers.length > maxTriggers) {
    return 'Pick $maxTriggers triggers or fewer';
  }

  if (triggers.any((String t) => t.isEmpty)) {
    return 'A trigger needs a name';
  }

  if (triggers.any((String t) => t.length > maxTriggerLength)) {
    return 'Keep each trigger to $maxTriggerLength characters or fewer';
  }

  return null;
}

// A habit's own unit label (and its form for one) and cost per unit live only inside its sealed
// envelope, so these are their only bounds; firestore.rules repeats them for a
// plaintext write, which this build never makes.
const int maxUnitLabelLength = 20;
const double maxCostPerUnit = 100000;

String? unitLabelError(String? value) {
  final String label = value?.trim() ?? '';
  if (label.length > maxUnitLabelLength) {
    return 'Use $maxUnitLabelLength characters or fewer';
  }

  return null;
}

String? costPerUnitError(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final num? cost = parseAmount(value);

  if (cost == null) {
    return 'Please enter a valid amount';
  }

  if (cost <= 0) {
    return 'Please enter more than 0';
  }

  if (cost > maxCostPerUnit) {
    return 'Please enter ${formatCount(maxCostPerUnit)} or less';
  }

  return null;
}

// An ISO 4217 code, as intl's currency formats take it.
final RegExp currencyCodePattern = RegExp(r'^[A-Z]{3}$');

// A habit's line lives only inside its sealed envelope, like the unit label;
// firestore.rules repeats the bound for a plaintext write.
const double maxLineAmount = 100000;

String? lineAmountError(String? value) {
  final num? amount = value == null ? null : parseAmount(value);

  if (amount == null) {
    return 'Please enter a valid number';
  }

  if (amount <= 0) {
    return 'Please enter more than 0';
  }

  if (amount > maxLineAmount) {
    return 'Please enter ${formatCount(maxLineAmount)} or less';
  }

  return null;
}
