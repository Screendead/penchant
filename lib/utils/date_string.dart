String get dateString => dateStringFromDate(DateTime.now());
String dateStringFromDate(DateTime date) =>
    date.toIso8601String().substring(0, 10);
