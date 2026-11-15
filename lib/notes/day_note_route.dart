/// The route of the note about the local day [day]: `/day-notes/2026-11-15`.
String dayNoteRoute(DateTime day) =>
    '/day-notes/${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
