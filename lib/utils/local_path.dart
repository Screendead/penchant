import 'package:path_provider/path_provider.dart';

Future<String> get localPath async =>
    (await getApplicationDocumentsDirectory()).path;
