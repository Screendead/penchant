import 'package:intl/intl.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/insights/insights_report.dart';

/// Words for the plan screen, Today's strip and the result cards.
class ExperimentWords {
  ExperimentWords(this.metricId, this.locale)
    : copy = metricCopy(metricId)!;

  final String metricId;
  final String locale;
  final MetricCopy copy;

  static String button(int weeks) => 'Test this for $weeks weeks';
  static const String buttonNote =
      'The app picks the evenings at random, so a busy week or a late night '
      'can’t explain the result.';
  static const String newTag = 'New';
  static const String howLong = 'How long';
  static const String daysHeading = 'Days';
  static const String starts = 'Starts';
  static const String ends = 'Ends';
  static const String noneDays = 'None days';
  static const String balance =
      'Every week has 3 or 4 of each, so weekends land on both sides.';
  static const String tellMe = 'Tell me each day';
  static const String notification = 'Notification';
  static const String notificationNote =
      'It says “Experiment, day 9 of 42: a none day”, never the habit’s name. '
      'Turning this on asks for notifications if you haven’t allowed them for '
      'the daily reminder.';
  static const String start = 'Start experiment';
  static const String stop = 'Stop experiment';
  static const String stopTitle = 'Stop this experiment?';
  static const String stopBody =
      'The plan and its notifications are removed, and no result is worked '
      'out.';
  static const String keepGoing = 'Keep going';
  static const String resultHeading = 'Your experiment';
  static const String runOn = 'Run it 4 more weeks';
  static const String permissionDenied =
      'Notifications are off for Penchant. Turn them on in the system '
      'Settings, then try again.';
  static const String noSpread =
      'Penchant needs two weeks of this measure to say how sure each length '
      'would be.';
  static const String startsTomorrow = 'Experiment starts tomorrow';
  static const String asUsualToday = 'As usual today';
  static const String noneLegend = 'none after 18:00';
  static const String usualLegend = 'as usual';

  bool get night => copy.night;
  String get name => copy.name;
  String get nights => night ? 'nights' : 'days';
  String get swing => night ? 'night-to-night' : 'day-to-day';

  static String hour(int h) => '${h.toString().padLeft(2, '0')}:00';

  String title(String habit) => 'Test $habit and $name';

  String rule(String habit, int fromHour) => 'no $habit after ${hour(fromHour)}';

  /// Around the bold [rule].
  ({String before, String after}) body(String habit) => (
    before: 'On days chosen at random, have ',
    after:
        '. On the others, do as you normally would. Penchant compares your '
        '$name on the two kinds of ${night ? 'night' : 'day after'}.',
  );

  String bodyNote(String habit, int fromHour) =>
      'It reads what you log: a $habit entry after ${hour(fromHour)} on a none '
      'day counts as a missed day, not a failure. You can stop at any time.';

  String plusMinus(double halfWidth) =>
      '±${_number(halfWidth, copy.decimals)}';

  String get _unitWords => copy.unit == 'min' ? 'minutes' : copy.unit;

  /// Under the length chips: how sure each would be, and what the chosen one
  /// would likely tell of the finding's size.
  String spreadNote({
    required double spread,
    required double finding,
    required int weeks,
  }) {
    final double chosen = expectedPower(finding, spread, weeks);
    final double shortest = expectedPower(
      finding,
      spread,
      experimentLengths.first,
    );
    final String told = chosen >= 0.7
        ? 'would usually tell that from no difference'
        : chosen >= 0.4
        ? 'would tell that from no difference about half the time'
        : 'would seldom tell that from no difference';
    final String two =
        weeks != experimentLengths.first && shortest < 0.4
        ? '; ${experimentLengths.first} weeks seldom would'
        : '';
    return 'How sure the answer will be, in $_unitWords either way, from how '
        'much your $name already varies $swing '
        '(${measureAmount(spread, copy, copy.decimals, locale)}). The finding '
        'was ${measureAmount(finding, copy, copy.decimals, locale)}: $weeks '
        'weeks $told$two.';
  }

  String noneOf(ExperimentPlan plan) => '${plan.noneDays} of ${plan.days}';

  String stripTitle(String habit, bool? none, int fromHour) => switch (none) {
    true => 'No $habit after ${hour(fromHour)} today',
    false => asUsualToday,
    null => startsTomorrow,
  };

  String stripLine(String habit, int? day, int of) => day == null
      ? '$habit and $name · $of days'
      : '$habit and $name · day $day of $of';

  String header(String habit, DateTime finished) =>
      '$habit · $name · finished ${DateFormat.MMMd(locale).format(finished)}';

  String _amount(double v) => measureAmount(v, copy, copy.decimals, locale);

  String _number(double v, int decimals) => NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: decimals,
  ).format(v.abs() * copy.scale);

  String sentence(String habit, ExperimentResult r, int fromHour) {
    final String amount = _amount(r.difference);
    final String dir = copy.direction(r.difference);
    final String h = hour(fromHour);
    if (r.clear) {
      return night
          ? 'On the nights you had no $habit after $h, your $name was $amount '
                '$dir than on the other nights.'
          : 'On the days after you had no $habit after $h, your $name was '
                '$amount $dir than after the other days.';
    }
    return night
        ? 'Can’t tell: on the nights with no $habit after $h, your $name was '
              '$amount $dir, inside your usual $swing swing.'
        : 'Can’t tell: on the days after no $habit after $h, your $name was '
              '$amount $dir, inside your usual $swing swing.';
  }

  /// "Range: 2 to 22 min more", or across zero "Range: 10 min less to 22 min
  /// more".
  String range(double low, double high) {
    if (low < 0 && high > 0) {
      return 'Range: ${_amount(low)} ${copy.direction(low)} to '
          '${_amount(high)} ${copy.direction(high)}';
    }
    final bool down = high <= 0;
    final double near = down ? high : low, far = down ? low : high;
    return 'Range: ${_number(near, copy.decimals)} to ${_amount(far)} '
        '${copy.direction(down ? -1 : 1)}';
  }

  String basis(ExperimentResult r, MetricFamily? family) {
    final String each = r.noneValues == r.usualValues
        ? '${r.noneValues} of each'
        : '${r.noneValues} after none days and ${r.usualValues} as usual';
    final String gap = r.missing == 0
        ? ''
        : ' (${r.missing} had no ${family?.label ?? 'Health'} data)';
    return 'From ${r.values} $nights, $each$gap';
  }

  String shortBasis(ExperimentResult r) => 'From ${r.values} $nights';

  String kept(String habit, ExperimentResult r, int fromHour) {
    if (r.missed == 0) return 'Plan kept on all ${r.days.length} days';
    final String days = r.missed == 1 ? 'none day' : 'none days';
    return 'Plan kept on ${r.kept} of ${r.days.length} days: $habit was logged '
        'after ${hour(fromHour)} on ${r.missed} $days, counted where they were '
        'planned';
  }

  static String missedLegend(String habit) => '$habit on a none day';

  /// The finding tested, turned to the experiment's direction (after none
  /// days less after as-usual ones).
  String before(ExperimentPlan plan) {
    final double effect = -plan.finding.effect;
    final double a = -plan.finding.high, b = -plan.finding.low;
    return 'Before the experiment your journal showed ${_amount(effect)} '
        '${copy.direction(effect)} '
        '(${_number(a.abs() < b.abs() ? a : b, copy.decimals)} to '
        '${_number(a.abs() < b.abs() ? b : a, copy.decimals)}). Because the '
        'days were picked at random, this one is the stronger evidence.';
  }

  static const String tooFew =
      'Too few nights with Health data on one side to compare.';
}
