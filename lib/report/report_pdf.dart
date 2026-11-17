import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tracker/data/day.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/report/report_data.dart';

// The Red Hat cuts the PDF embeds (tools/pdf-fonts.py), as bytes.
class ReportFonts {
  ReportFonts({
    required ByteData display,
    required ByteData text,
    required ByteData textBold,
    required ByteData mono,
    required ByteData monoBold,
  }) : display = pw.Font.ttf(display),
       text = pw.Font.ttf(text),
       textBold = pw.Font.ttf(textBold),
       mono = pw.Font.ttf(mono),
       monoBold = pw.Font.ttf(monoBold);

  static const List<String> assets = <String>[
    'assets/fonts/pdf/RedHatDisplay-Bold.ttf',
    'assets/fonts/pdf/RedHatText-Regular.ttf',
    'assets/fonts/pdf/RedHatText-SemiBold.ttf',
    'assets/fonts/pdf/RedHatMono-Regular.ttf',
    'assets/fonts/pdf/RedHatMono-SemiBold.ttf',
  ];

  final pw.Font display;
  final pw.Font text;
  final pw.Font textBold;
  final pw.Font mono;
  final pw.Font monoBold;
}

// The regions that print on US Letter; everywhere else uses A4.
const Set<String> letterRegions = <String>{
  'US', 'CA', 'MX', 'PR', 'PH', 'CL', 'CO', 'VE', 'GT', 'CR', 'PA', 'DO', //
  'SV', 'NI', 'HN', 'BZ',
};

PdfPageFormat reportPaper(Locale locale) =>
    letterRegions.contains(locale.countryCode)
    ? PdfPageFormat.letter
    : PdfPageFormat.a4;

const PdfColor _ink = PdfColors.black;
const PdfColor _muted = PdfColor(0.36, 0.36, 0.36);
const PdfColor _faint = PdfColor(0.62, 0.62, 0.62);
const PdfColor _rule = PdfColor(0.78, 0.78, 0.78);
const PdfColor _shade = PdfColor(0.9, 0.9, 0.9);
// Light enough at full strength for black figures on them.
const PdfColor _low = PdfColor(0.47, 0.78, 0.5);
const PdfColor _high = PdfColor(0.94, 0.45, 0.4);
const PdfColor _none = PdfColor(0.13, 0.13, 0.13);

PdfColor _scoreColour(double score) {
  final double t = (score.abs() / dayScoreFullAt).clamp(0, 1);
  final PdfColor end = score < 0 ? _low : _high;
  double mix(double a) => 1 + (a - 1) * t;
  return PdfColor(mix(end.red), mix(end.green), mix(end.blue));
}

const PdfColor _barColour = PdfColor(0.45, 0.45, 0.45);

Future<Uint8List> reportPdf(
  ReportData data,
  ReportFonts fonts, {
  required PdfPageFormat format,
}) => reportDocument(data, fonts, format: format).save();

pw.Document reportDocument(
  ReportData data,
  ReportFonts fonts, {
  required PdfPageFormat format,
}) {
  final _Styles s = _Styles(fonts);
  // No author, subject or keywords: nothing names the account.
  final pw.Document doc = pw.Document(
    title: 'Penchant report',
    creator: 'Penchant',
    theme: pw.ThemeData.withFont(base: fonts.text, bold: fonts.textBold),
  );
  final String period =
      '${_longDate(data.window.start)} to '
      '${_longDate(addDays(data.window.end, -1))}';
  // One run of pages per habit, so each starts on a new page and every page
  // names the habit it shows.
  void section(String name, List<pw.Widget> body) => doc.addPage(
    pw.MultiPage(
      // White drawn, not assumed: the preview rasters a page with no
      // background as transparent, which dark mode shows as black.
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
        buildBackground: (pw.Context context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: PdfColors.white),
        ),
      ),
      maxPages: 400,
      header: (pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.only(bottom: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Text('Penchant', style: s.brand),
            pw.SizedBox(width: 8),
            pw.Text(period, style: s.small),
            pw.Spacer(),
            pw.Text(name, style: s.section),
          ],
        ),
      ),
      footer: (pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          children: <pw.Widget>[
            pw.Text(
              'Made ${_longDate(data.made)} from entries logged in Penchant. '
              'Days run midnight to midnight, local time.',
              style: s.tinyMuted,
            ),
            pw.Spacer(),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: s.tiny,
            ),
          ],
        ),
      ),
      build: (pw.Context context) => body,
    ),
  );

  if (data.habits.isEmpty) {
    section('', <pw.Widget>[
      ..._intro(data, s),
      pw.Text('No habits chosen.', style: s.body),
    ]);
  }
  for (final (int i, HabitReport habit) in data.habits.indexed) {
    section(habit.name, <pw.Widget>[
      if (i == 0) ..._intro(data, s),
      ..._habit(data, habit, s),
    ]);
  }
  if (data.dayNotes.isNotEmpty) {
    section('Day notes', <pw.Widget>[
      _sectionTitle('Day notes', s),
      ..._noteRows(data.dayNotes, s, withTime: false),
    ]);
  }
  return doc;
}

class _Styles {
  _Styles(ReportFonts f)
    : brand = pw.TextStyle(font: f.display, fontSize: 11, color: _ink),
      title = pw.TextStyle(font: f.display, fontSize: 20, color: _ink),
      section = pw.TextStyle(font: f.textBold, fontSize: 9.5, color: _ink),
      body = pw.TextStyle(font: f.text, fontSize: 8.5, color: _ink),
      bodyMuted = pw.TextStyle(font: f.text, fontSize: 8.5, color: _muted),
      small = pw.TextStyle(font: f.text, fontSize: 8, color: _ink),
      smallMuted = pw.TextStyle(font: f.text, fontSize: 8, color: _muted),
      tiny = pw.TextStyle(font: f.text, fontSize: 6.5, color: _ink),
      tinyMuted = pw.TextStyle(font: f.text, fontSize: 6.5, color: _muted),
      month = pw.TextStyle(font: f.textBold, fontSize: 8.5, color: _ink),
      weekday = pw.TextStyle(font: f.text, fontSize: 6, color: _muted),
      dayNumber = pw.TextStyle(font: f.mono, fontSize: 5.5, color: _faint),
      dayTotal = pw.TextStyle(font: f.monoBold, fontSize: 9, color: _ink),
      statValue = pw.TextStyle(font: f.display, fontSize: 15, color: _ink),
      statLabel = pw.TextStyle(font: f.text, fontSize: 7, color: _muted),
      figure = pw.TextStyle(font: f.mono, fontSize: 8, color: _ink),
      figureBold = pw.TextStyle(font: f.monoBold, fontSize: 8, color: _ink);

  final pw.TextStyle brand;
  final pw.TextStyle title;
  final pw.TextStyle section;
  final pw.TextStyle body;
  final pw.TextStyle bodyMuted;
  final pw.TextStyle small;
  final pw.TextStyle smallMuted;
  final pw.TextStyle tiny;
  final pw.TextStyle tinyMuted;
  final pw.TextStyle month;
  final pw.TextStyle weekday;
  final pw.TextStyle dayNumber;
  final pw.TextStyle dayTotal;
  final pw.TextStyle statValue;
  final pw.TextStyle statLabel;
  final pw.TextStyle figure;
  final pw.TextStyle figureBold;
}

String _longDate(DateTime day) => formatDate(day);

String _figure(double value) => formatCount(_round(value));

// Totals of decimal amounts print to two places at most.
num _round(double value) => value == value.roundToDouble()
    ? value.round()
    : (value * 100).round() / 100;

List<pw.Widget> _intro(ReportData data, _Styles s) {
  final List<String> left = <String>[
    if (data.lockedEntries > 0)
      '${formatCount(data.lockedEntries)} '
          '${pluralWord(data.lockedEntries, one: 'entry', other: 'entries')}',
    if (data.lockedHabits > 0)
      '${formatCount(data.lockedHabits)} '
          '${pluralWord(data.lockedHabits, one: 'habit', other: 'habits')}',
  ];
  return <pw.Widget>[
    pw.Text(
      data.notesIncluded
          ? 'Notes written by the person are included.'
          : 'Notes and tags in the person’s own words are not included.',
      style: s.smallMuted,
    ),
    if (left.isNotEmpty)
      pw.Text(
        'Left out: ${left.join(' and ')} that could not be opened on the '
        'device that made this report.',
        style: s.smallMuted,
      ),
    pw.SizedBox(height: 10),
  ];
}

List<pw.Widget> _habit(ReportData data, HabitReport habit, _Styles s) {
  final String unitWord = habit.units.plural;
  return <pw.Widget>[
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.SizedBox(
          width: 14,
          height: 14,
          child: pw.CustomPaint(
            size: const PdfPoint(14, 14),
            painter: (PdfGraphics g, PdfPoint size) =>
                _paintMark(g, habit.mark, size),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(child: pw.Text(habit.name, style: s.title)),
      ],
    ),
    pw.Padding(
      padding: const pw.EdgeInsets.only(left: 22, top: 2),
      child: pw.Text(
        <String>[
          'Counted in $unitWord',
          if (habit.strength != null)
            'one ${habit.units.singular} is '
                '${habit.strength!.describe}, counted as ${habit.strength!.noun}',
        ].join('; '),
        style: s.bodyMuted,
      ),
    ),
    pw.SizedBox(height: 10),
    _stats(data, habit, s),
    pw.SizedBox(height: 14),
    ..._calendars(data, habit, s),
    pw.SizedBox(height: 6),
    ..._weeks(habit, s),
    pw.SizedBox(height: 14),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(child: _hours(data, habit, s)),
        pw.SizedBox(width: 24),
        pw.Expanded(child: _tags(habit, s)),
      ],
    ),
    if (habit.notes.isNotEmpty) ...<pw.Widget>[
      pw.SizedBox(height: 14),
      _sectionTitle('Notes on entries', s),
      ..._noteRows(habit.notes, s, withTime: true),
    ],
  ];
}

pw.Widget _stats(ReportData data, HabitReport habit, _Styles s) {
  final double? units = habit.unitsTotal;
  final List<(String, String)> stats = <(String, String)>[
    (_figure(habit.total), 'Total ${habit.units.nameFor(habit.total)}'),
    (
      '${formatCount(habit.daysWithEntries)} of ${formatCount(data.dayCount)}',
      'Days with an entry',
    ),
    (
      formatAverage(data.dayCount == 0 ? 0 : habit.total / data.dayCount),
      'Average a day',
    ),
    (formatCount(habit.entries), 'Entries'),
    if (units != null)
      (habit.strength!.number(units), 'Total ${habit.strength!.noun}'),
  ];
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 7),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: _rule, width: 0.6),
        bottom: pw.BorderSide(color: _rule, width: 0.6),
      ),
    ),
    child: pw.Row(
      children: <pw.Widget>[
        for (final (String value, String label) in stats)
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(value, style: s.statValue),
                pw.SizedBox(height: 1),
                pw.Text(label, style: s.statLabel),
              ],
            ),
          ),
      ],
    ),
  );
}

const int _monthsPerRow = 3;
const double _cellHeight = 23;
const double _monthGap = 14;

List<pw.Widget> _calendars(ReportData data, HabitReport habit, _Styles s) {
  final List<DateTime> months = <DateTime>[
    for (
      DateTime m = data.window.start;
      m.isBefore(data.window.end);
      m = DateTime(m.year, m.month + 1)
    )
      m,
  ];
  return <pw.Widget>[
    pw.Row(
      children: <pw.Widget>[
        _sectionTitle('Each day', s),
        pw.Spacer(),
        for (final (PdfColor colour, String label) in <(PdfColor, String)>[
          (_low, 'less than usual'),
          (PdfColors.white, 'usual'),
          (_high, 'more than usual'),
          (_none, 'none logged'),
        ]) ...<pw.Widget>[
          pw.SizedBox(width: 6),
          pw.Container(
            width: 9,
            height: 7,
            decoration: pw.BoxDecoration(
              color: colour,
              border: pw.Border.all(color: _rule, width: 0.4),
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(label, style: s.tinyMuted),
        ],
      ],
    ),
    pw.Text(
      'Shaded by how far each day sits from the average of this period’s '
      'days with an entry; strongest at two standard deviations.',
      style: s.tinyMuted,
    ),
    pw.SizedBox(height: 4),
    for (int i = 0; i < months.length; i += _monthsPerRow)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            for (int j = 0; j < _monthsPerRow; j++) ...<pw.Widget>[
              if (j > 0) pw.SizedBox(width: _monthGap),
              pw.Expanded(
                child: i + j < months.length
                    ? _month(data, habit, months[i + j], s)
                    : pw.SizedBox(),
              ),
            ],
          ],
        ),
      ),
  ];
}

pw.Widget _month(
  ReportData data,
  HabitReport habit,
  DateTime month,
  _Styles s,
) {
  final int lead = (month.weekday - data.firstWeekday) % 7;
  final int length = DateTime(month.year, month.month + 1, 0).day;
  final int rows = ((lead + length) / 7).ceil();
  final DateFormat weekdayLetter = DateFormat.E(formatLocale);
  final List<double?> scores = dayScores(habit.days);
  pw.Widget cell(int index) {
    final int day = index - lead + 1;
    if (day < 1 || day > length) {
      return pw.Expanded(child: pw.SizedBox(height: _cellHeight));
    }
    final DateTime date = DateTime(month.year, month.month, day);
    final int offset = daysBetween(data.window.start, date);
    final bool inWindow = offset >= 0 && offset < habit.days.length;
    final double total = inWindow ? habit.days[offset] : 0;
    final double? score = inWindow ? scores[offset] : null;
    return pw.Expanded(
      child: pw.Container(
        height: _cellHeight,
        decoration: pw.BoxDecoration(
          color: !inWindow
              ? null
              : score == null
              ? _none
              : _scoreColour(score),
          border: pw.Border.all(color: _rule, width: 0.4),
        ),
        child: pw.Stack(
          children: <pw.Widget>[
            pw.Positioned(
              left: 1.5,
              top: 1,
              child: pw.Text(
                '$day',
                style: !inWindow
                    ? s.dayNumber.copyWith(color: _rule)
                    : score == null
                    ? s.dayNumber.copyWith(color: _rule)
                    : s.dayNumber.copyWith(color: _muted),
              ),
            ),
            if (total > 0)
              pw.Positioned.fill(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Center(
                    child: pw.Text(
                      _figure(total),
                      style: total >= 100
                          ? s.dayTotal.copyWith(fontSize: 7)
                          : s.dayTotal,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: <pw.Widget>[
      pw.Text(formatMonth(month), style: s.month),
      pw.SizedBox(height: 3),
      pw.Row(
        children: <pw.Widget>[
          for (int d = 0; d < 7; d++)
            pw.Expanded(
              child: pw.Center(
                child: pw.Text(
                  weekdayLetter.format(
                    DateTime(2024, 1, data.firstWeekday + d),
                  ),
                  style: s.weekday,
                ),
              ),
            ),
        ],
      ),
      pw.SizedBox(height: 2),
      for (int r = 0; r < rows; r++)
        pw.Row(
          children: <pw.Widget>[for (int c = 0; c < 7; c++) cell(r * 7 + c)],
        ),
    ],
  );
}

List<pw.Widget> _weeks(HabitReport habit, _Styles s) {
  final bool units = habit.strength != null;
  final double most = habit.weeks.fold<double>(
    0,
    (double a, ReportWeek w) => math.max(a, w.total),
  );
  final DateFormat short = DateFormat.MMMd(formatLocale);
  // Two columns of weeks once there are more than fit beside the page's
  // other sections, so a year stays on as few pages as it can.
  final int columns = habit.weeks.length > 16 ? 2 : 1;
  final int perColumn = (habit.weeks.length / columns).ceil();

  pw.Widget row(ReportWeek week) {
    final DateTime last = addDays(week.start, week.days - 1);
    return pw.Container(
      height: 12.5,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _shade, width: 0.5)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(
            width: 82,
            child: pw.Text(
              '${short.format(week.start)} – ${short.format(last)}',
              style: s.small,
            ),
          ),
          pw.SizedBox(
            width: 34,
            child: pw.Text(
              week.days < 7
                  ? '${week.days} ${pluralWord(week.days, one: 'day', other: 'days')}'
                  : '',
              style: s.tinyMuted,
            ),
          ),
          pw.Expanded(child: _bar(most == 0 ? 0 : week.total / most)),
          pw.SizedBox(
            width: 36,
            child: pw.Text(
              _figure(week.total),
              style: s.figureBold,
              textAlign: pw.TextAlign.right,
            ),
          ),
          if (units)
            pw.SizedBox(
              width: 46,
              child: pw.Text(
                habit.strength!.number(week.units ?? 0),
                style: s.figure,
                textAlign: pw.TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget head() => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 2),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.5)),
    ),
    child: pw.Row(
      children: <pw.Widget>[
        pw.SizedBox(width: 82, child: pw.Text('Week', style: s.tinyMuted)),
        pw.Expanded(child: pw.SizedBox()),
        pw.SizedBox(
          width: 36,
          child: pw.Text(
            _capitalised(habit.units.plural),
            style: s.tinyMuted,
            textAlign: pw.TextAlign.right,
          ),
        ),
        if (units)
          pw.SizedBox(
            width: 46,
            child: pw.Text(
              _capitalised(habit.strength!.noun),
              style: s.tinyMuted,
              textAlign: pw.TextAlign.right,
            ),
          ),
      ],
    ),
  );

  return <pw.Widget>[
    _sectionTitle('Each week', s),
    pw.SizedBox(height: 3),
    // Each line is its own child so a long period breaks between weeks.
    for (int i = -1; i < perColumn; i++)
      pw.Row(
        children: <pw.Widget>[
          for (int c = 0; c < columns; c++) ...<pw.Widget>[
            if (c > 0) pw.SizedBox(width: 24),
            pw.Expanded(
              child: i < 0
                  ? head()
                  : c * perColumn + i < habit.weeks.length
                  ? row(habit.weeks[c * perColumn + i])
                  : pw.SizedBox(),
            ),
          ],
        ],
      ),
    if (units && habit.unitsWithout > 0)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Text(
          '${formatCount(habit.unitsWithout)} '
          '${pluralWord(habit.unitsWithout, one: 'entry has', other: 'entries have')} '
          'no strength and '
          '${pluralWord(habit.unitsWithout, one: 'is', other: 'are')} '
          'not in the ${habit.strength!.noun} column.',
          style: s.tinyMuted,
        ),
      ),
  ];
}

// A horizontal bar filling [share] of its width.
pw.Widget _bar(double share) {
  final int filled = (share * 1000).round();
  return pw.Row(
    children: <pw.Widget>[
      if (filled > 0)
        pw.Expanded(
          flex: filled,
          child: pw.Container(height: 5, color: _barColour),
        ),
      if (filled < 1000)
        pw.Expanded(flex: 1000 - filled, child: pw.SizedBox(height: 5)),
    ],
  );
}

String _capitalised(String word) =>
    word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';

pw.Widget _hours(ReportData data, HabitReport habit, _Styles s) {
  final List<double> hours = habit.hours.hours;
  final double most = hours.fold<double>(0, math.max);
  final int start = habit.hours.busiestStart;
  final String span = habit.hourDays < data.dayCount
      ? 'Over the last ${formatCount(habit.hourDays)} days of the period'
      : 'Over the whole period';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _sectionTitle('Time of day', s),
      pw.SizedBox(height: 2),
      pw.Text(
        habit.hours.total == 0
            ? 'Nothing logged.'
            : 'Busiest: ${_hour(start)} to ${_hour((start + 3) % 24)}. '
                  '${habit.hours.beforeNoonPercent}% before noon.',
        style: s.small,
      ),
      pw.Text(span, style: s.tinyMuted),
      pw.SizedBox(height: 6),
      pw.SizedBox(
        height: 46,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            for (int h = 0; h < 24; h++)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 0.6),
                  child: pw.Container(
                    height: most == 0 ? 0 : 46 * hours[h] / most,
                    color: _barColour,
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.Container(height: 0.5, color: _ink),
      pw.SizedBox(height: 2),
      pw.Row(
        children: <pw.Widget>[
          for (int h = 0; h < 24; h += 6)
            pw.Expanded(flex: 6, child: pw.Text(_hour(h), style: s.tinyMuted)),
        ],
      ),
    ],
  );
}

String _hour(int hour) => '${hour.toString().padLeft(2, '0')}:00';

pw.Widget _tags(HabitReport habit, _Styles s) {
  final int most = habit.tags.isEmpty ? 0 : habit.tags.first.entries;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _sectionTitle('Most common tags', s),
      pw.SizedBox(height: 2),
      pw.Text(
        habit.entries == 0
            ? 'Nothing logged.'
            : '${formatCount(habit.taggedEntries)} of '
                  '${formatCount(habit.entries)} '
                  '${pluralWord(habit.entries, one: 'entry', other: 'entries')} '
                  'tagged.',
        style: s.small,
      ),
      pw.SizedBox(height: 6),
      for (final ReportTag tag in habit.tags)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                flex: 5,
                child: pw.Text(tag.label, style: s.small, maxLines: 1),
              ),
              pw.Expanded(
                flex: 3,
                child: _bar(tag.entries / math.max(1, most)),
              ),
              pw.SizedBox(
                width: 22,
                child: pw.Text(
                  formatCount(tag.entries),
                  style: s.figure,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _sectionTitle(String text, _Styles s) =>
    pw.Text(text, style: s.section);

List<pw.Widget> _noteRows(
  List<ReportNote> notes,
  _Styles s, {
  required bool withTime,
}) {
  final DateFormat day = DateFormat.yMMMd(formatLocale);
  return <pw.Widget>[
    pw.SizedBox(height: 4),
    for (final ReportNote note in notes)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.SizedBox(
              width: 96,
              child: pw.Text(
                withTime
                    ? '${day.format(note.at)}, ${formatClock(note.at)}'
                    : day.format(note.at),
                style: s.smallMuted,
              ),
            ),
            pw.Expanded(child: pw.Text(note.text, style: s.body)),
          ],
        ),
      ),
  ];
}

// Black on white, so habits differ by shape: the app's style (filled, ring,
// dotted ring) over a shape for each of its five colour slots.
void _paintMark(PdfGraphics g, HabitMark mark, PdfPoint size) {
  final double c = size.x / 2;
  final double r = size.x / 2 - 1;
  switch (mark.slot) {
    case 0:
      g.drawEllipse(c, c, r, r);
    case 1:
      g.drawRect(c - r * 0.88, c - r * 0.88, r * 1.76, r * 1.76);
    case 2:
      g
        ..moveTo(c, c + r)
        ..lineTo(c + r, c)
        ..lineTo(c, c - r)
        ..lineTo(c - r, c)
        ..closePath();
    case 3:
      g
        ..moveTo(c, c + r)
        ..lineTo(c + r * 0.95, c - r * 0.75)
        ..lineTo(c - r * 0.95, c - r * 0.75)
        ..closePath();
    default:
      for (int i = 0; i < 6; i++) {
        final double a = math.pi / 6 + i * math.pi / 3;
        final double x = c + r * math.cos(a);
        final double y = c + r * math.sin(a);
        i == 0 ? g.moveTo(x, y) : g.lineTo(x, y);
      }
      g.closePath();
  }
  switch (mark.style) {
    case HabitMarkStyle.filled:
      g
        ..setFillColor(_ink)
        ..fillPath();
    case HabitMarkStyle.ring:
      g
        ..setStrokeColor(_ink)
        ..setLineWidth(1.4)
        ..strokePath();
    case HabitMarkStyle.dotted:
      g
        ..setStrokeColor(_ink)
        ..setLineWidth(1.4)
        ..setLineDashPattern(<num>[1.4, 1.6])
        ..strokePath();
  }
}
