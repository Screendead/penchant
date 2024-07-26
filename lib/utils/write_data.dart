import 'dart:convert';
import 'dart:io';

import 'package:tracker/utils/local_file.dart';

Future<File> writeData(Map<String, dynamic> data) async =>
    (await localFile).writeAsString(jsonEncode(data));
