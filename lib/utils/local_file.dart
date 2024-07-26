import 'dart:io';

import 'package:tracker/utils/date_string.dart';
import 'package:tracker/utils/local_path.dart';

Future<File> get localFile async =>
    File('${await localPath}/data-$dateString.json');
