import 'dart:convert';

import 'package:tracker/data/sealed.dart';

// A reversible stand-in for the real cipher: no secrecy, but the stored
// envelope holds no field in the clear, and it opens only for its document.
class FakeSealer implements FieldSealer {
  static const String prefix = 'fake.';

  final List<String> opened = <String>[];

  @override
  Future<String> seal(
    Map<String, Object?> fields, {
    required String context,
  }) async =>
      prefix +
      base64Url.encode(
        utf8.encode(jsonEncode(<String, Object?>{'c': context, 'f': fields})),
      );

  @override
  Future<Map<String, Object?>> open(
    String envelope, {
    required String context,
  }) async {
    if (!envelope.startsWith(prefix)) {
      throw const FormatException('not a fake envelope');
    }
    final Object? decoded = jsonDecode(
      utf8.decode(base64Url.decode(envelope.substring(prefix.length))),
    );
    if (decoded case {
      'c': final String sealedFor,
      'f': final Map<String, Object?> fields,
    } when sealedFor == context) {
      opened.add(context);
      return fields;
    }
    throw const FormatException('sealed for another document');
  }
}
