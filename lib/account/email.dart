final RegExp emailPattern = RegExp(
  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
);

String? emailError(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter your email address';
  }
  if (!emailPattern.hasMatch(value)) {
    return 'Please enter a valid email address';
  }
  return null;
}
