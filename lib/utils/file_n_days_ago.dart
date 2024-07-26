import 'dart:io';

import 'package:tracker/utils/date_string.dart';
import 'package:tracker/utils/local_path.dart';

Future<File> fileNDaysAgo(int n) async {
  final String dateString = dateStringFromDate(
    DateTime.now().subtract(Duration(days: n)),
  );
  return File('${await localPath}/data-$dateString.json');
}
