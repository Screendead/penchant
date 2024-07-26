import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> readData(File file) async {
  try {
    return Map<String, dynamic>.from(
      jsonDecode(
        await (file).readAsString(),
      ),
    );
  } catch (e) {
    return {};
  }
}
