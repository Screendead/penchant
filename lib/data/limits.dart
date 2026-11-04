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

// The rules check quantity only when an update changes it, so a legacy
// activity's out-of-range value can be saved back as it is.
String? quantityError(String? value, {int? unchanged}) {
  if (value == null || value.isEmpty) {
    return 'Please enter a quantity';
  }

  final int? quantity = int.tryParse(value);

  if (quantity == null) {
    return 'Please enter a valid number';
  }

  if (quantity < 1 && quantity != unchanged) {
    return 'Please enter at least 1';
  }

  return null;
}
