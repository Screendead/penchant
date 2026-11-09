import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/settings_card.dart';

/// What follows each habit, from the whole journal and Apple Health, worked
/// out on the device.
class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  static const String route = '/insights';
  static const String title = 'Insights';
  static const String connectLabel = 'Connect Apple Health';
  static const String loadingLabel = 'Working out your insights';
  static const String noHealthData = 'No Health data to read';
  static const String noHealthDataBody =
      'Penchant found no sleep, heart or activity data. '
      'If you didn’t allow it to read Health, find Health in Settings and '
      'turn it on under Data Access & Devices > Penchant.';
  static const String noHealthDataValue = 'No data';
  static const String nothingClear = 'Nothing clear yet';
  static const String onIPhone = 'Available on iPhone';
  static const String refusedHeading = 'Not enough to say';
  static const String foundHeading = 'What follows';
  static const String nothingClearBody =
      'No habit has a difference that stands out from your usual days yet.';
  static const String copyLabel = 'Copy as text';
  static const String copied = 'Insights copied';
  static const String foot =
      'Worked out on this device from your journal and Apple Health; '
      'Health data never leaves it. These are patterns in your own days, '
      'not medical advice, and a pattern doesn’t show that one thing '
      'causes another.';

  static String span(DateTime firstDay) =>
      'From ${formatDate(firstDay)} to today';

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  bool _connecting = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Access granted in Settings shows no sheet, so coming back is the only
    // sign that Health may now have data to give.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (ref.read(healthStateProvider).value case HealthReady(
          :final values,
        ) when values.isEmpty) {
          _retryHealth();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    setState(() => _connecting = true);
    final bool shown = await connectHealth(container);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (!shown) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Apple Health couldn’t be opened.')),
      );
    }
  }

  // A new read gives new values, so the engine runs again too.
  void _retryHealth() => ref.invalidate(healthStateProvider);

  void _retryJournal() => ref.invalidate(viceActivityRangeForUserProvider);

  void _retryHabits() => ref.invalidate(viceListForUserProvider);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<InsightsView> view = ref.watch(insightsProvider);
    final AsyncValue<List<Vice>> habits = ref.watch(viceListProvider);
    final List<Vice>? vices = habits.value;
    final Map<String, String> names = <String, String>{
      for (final Vice v in vices ?? const <Vice>[]) v.id: v.name,
    };
    // Health's state is known before the journal loads, so the card shows it.
    final HealthState? health =
        view.value?.health ?? ref.watch(healthStateProvider).value;

    return CardPage(
      title: InsightsPage.title,
      children: <Widget>[
        _HealthCard(
          state: health,
          connecting: _connecting,
          onConnect: _connect,
        ),
        ...switch (view) {
          AsyncError() => <Widget>[
            const SizedBox(height: DialSpace.l),
            InfoBox(
              message: 'Your journal couldn’t be loaded.',
              isError: true,
              onRetry: _retryJournal,
            ),
          ],
          _ when habits is AsyncError && vices == null => <Widget>[
            const SizedBox(height: DialSpace.l),
            InfoBox(
              message: 'Your habits couldn’t be loaded.',
              isError: true,
              onRetry: _retryHabits,
            ),
          ],
          AsyncData(:final InsightsView value) when vices != null => _body(
            value,
            names,
          ),
          _ => const <Widget>[
            _MessageCard(InsightsPage.loadingLabel, busy: true),
          ],
        },
        const CardFoot(InsightsPage.foot),
      ],
    );
  }

  List<Widget> _body(InsightsView view, Map<String, String> names) {
    String nameOf(String id) => names[id] ?? 'a removed habit';
    switch (view.health) {
      case HealthOnIPhone():
        return const <Widget>[
          _MessageCard(
            'Insights',
            body:
                'Open Penchant on your iPhone to see what follows each '
                'habit. Apple Health keeps its data there.',
          ),
        ];
      case HealthUnsupported():
        return const <Widget>[
          _MessageCard(
            'Insights',
            body: 'Insights need Apple Health, which this device doesn’t have.',
          ),
        ];
      case HealthNotConnected():
        return const <Widget>[
          _MessageCard(
            'How it works',
            body:
                'Insights compare your sleep, heart and activity after days '
                'with each habit against days without it. Connect Apple '
                'Health to start.',
          ),
        ];
      case HealthLocked():
        return <Widget>[
          _MessageCard(
            'Health is locked',
            body:
                'Apple Health can’t be read while your iPhone is locked. '
                'Unlock it and try again.',
            onRetry: _retryHealth,
          ),
        ];
      case HealthFailed():
        return <Widget>[
          _MessageCard(
            'Health couldn’t be read',
            body: 'Try again in a moment.',
            onRetry: _retryHealth,
          ),
        ];
      case HealthReady():
        break;
    }
    final InsightsResult? result = view.result;
    if (result == null) {
      // HealthKit answers a refused read with no samples, so this can't tell
      // an empty Health from access that wasn't allowed.
      return <Widget>[
        _MessageCard(
          InsightsPage.noHealthData,
          body: InsightsPage.noHealthDataBody,
          onRetry: _retryHealth,
        ),
      ];
    }
    if (result is InsightsFailed) {
      return <Widget>[
        _MessageCard(
          'Insights couldn’t be worked out',
          body: 'Try again in a moment.',
          onRetry: _retryHealth,
        ),
      ];
    }
    final InsightsComputed computed = result as InsightsComputed;
    final InsightsReport report = computed.report;
    final List<HabitFinding> findings = <HabitFinding>[
      for (final HabitFinding f in report.findings)
        if (names.containsKey(f.habitId)) f,
    ];
    final List<HabitRefusal> refused = <HabitRefusal>[
      for (final HabitRefusal r in report.refused)
        if (names.containsKey(r.habitId)) r,
    ]..sort((a, b) => nameOf(a.habitId).compareTo(nameOf(b.habitId)));
    final String locale = formatLocale;
    final DateTime? firstDay = computed.firstDay;
    return <Widget>[
      if (firstDay != null) CardFoot(InsightsPage.span(firstDay)),
      const CardSectionLabel(InsightsPage.foundHeading),
      if (findings.isEmpty)
        const _MessageCard(
          InsightsPage.nothingClear,
          top: 0,
          body: InsightsPage.nothingClearBody,
        ),
      for (int i = 0; i < findings.length; i++)
        _FindingCard(
          finding: findings[i],
          habit: nameOf(findings[i].habitId),
          locale: locale,
          top: i == 0 ? 0 : DialSpace.s,
        ),
      if (refused.isNotEmpty) ...<Widget>[
        const CardSectionLabel(InsightsPage.refusedHeading),
        DialCard(
          top: 0,
          children: <Widget>[
            for (final HabitRefusal r in refused)
              CardRow(
                label: nameOf(r.habitId),
                subtitle: refusalReason(r, nameOf),
              ),
          ],
        ),
      ],
      DialCard(
        children: <Widget>[
          CardRow(
            label: InsightsPage.copyLabel,
            subtitle: 'To the clipboard, for a note or a message',
            onTap: () => _copy(
              insightsText(
                findings: findings,
                refused: refused,
                firstDay: firstDay,
                nameOf: nameOf,
                locale: locale,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // Health findings reach the clipboard only from this tap; nothing else may
  // copy or send them.
  Future<void> _copy(String text) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(InsightsPage.copied)));
  }
}

/// The findings and refusals as the page shows them, in plain text.
String insightsText({
  required List<HabitFinding> findings,
  required List<HabitRefusal> refused,
  required DateTime? firstDay,
  required String Function(String habitId) nameOf,
  required String locale,
}) {
  final StringBuffer out = StringBuffer(InsightsPage.title);
  if (firstDay != null) out.write('\n${InsightsPage.span(firstDay)}');
  out.write('\n\n${InsightsPage.foundHeading}\n');
  if (findings.isEmpty) {
    out.write(
      '${InsightsPage.nothingClear}: ${InsightsPage.nothingClearBody}\n',
    );
  }
  for (final HabitFinding f in findings) {
    final String habit = nameOf(f.habitId);
    out
      ..write('\n$habit · ${metricCopy(f.metricId)!.name}\n')
      ..write('${findingSentence(f, habit, locale)}\n')
      ..write('${findingRange(f, locale)}\n')
      ..write('${findingBasis(f, habit)}\n');
  }
  if (refused.isNotEmpty) {
    out.write('\n${InsightsPage.refusedHeading}\n');
    for (final HabitRefusal r in refused) {
      out.write('${nameOf(r.habitId)}: ${refusalReason(r, nameOf)}\n');
    }
  }
  out.write('\n${InsightsPage.foot}\n');
  return out.toString();
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.state,
    required this.connecting,
    required this.onConnect,
  });

  final HealthState? state;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final Widget row = switch (state) {
      HealthNotConnected() => CardRow(
        label: InsightsPage.connectLabel,
        subtitle: 'Sleep, heart and activity totals, read on this iPhone only',
        enabled: !connecting,
        glyph: connecting ? null : DialGlyph.right,
        trailing: connecting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: onConnect,
      ),
      HealthOnIPhone() => const CardRow(
        label: 'Apple Health',
        subtitle: 'Health data stays on your iPhone',
        value: Text(InsightsPage.onIPhone),
      ),
      HealthUnsupported() => const CardRow(
        label: 'Apple Health',
        value: Text('Not on this device'),
      ),
      null => const CardRow(label: 'Apple Health'),
      HealthReady(:final values) when values.isEmpty => const CardRow(
        label: 'Apple Health',
        subtitle: 'Nothing shared, or access not allowed',
        value: Text(InsightsPage.noHealthDataValue),
      ),
      _ => const CardRow(
        label: 'Apple Health',
        subtitle: 'Read on this iPhone only',
        value: Text('Connected'),
      ),
    };
    return DialCard(children: <Widget>[row]);
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(
    this.title, {
    this.body,
    this.busy = false,
    this.onRetry,
    this.top = DialSpace.l,
  });

  final String title;
  final String? body;
  final bool busy;
  final VoidCallback? onRetry;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool still = MediaQuery.disableAnimationsOf(context);
    return DialCard(
      top: top,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Semantics(
            liveRegion: busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: DialTypeScale.bodyL.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (busy && !still)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      body!,
                      style: DialTypeScale.body.copyWith(color: colors.muted),
                    ),
                  ),
                if (onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: DialSpace.xs),
                    child: TextButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.habit,
    required this.locale,
    required this.top,
  });

  final HabitFinding finding;
  final String habit;
  final String locale;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final MetricCopy copy = metricCopy(finding.metricId)!;
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    return DialCard(
      top: top,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$habit · ${copy.name}',
                style: DialTypeScale.label.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 6),
              Text(
                findingSentence(finding, habit, locale),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: DialSpace.s),
              ExcludeSemantics(
                child: SizedBox(
                  height: 14,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RangePainter(
                      finding: finding,
                      ink: scheme.onSurface,
                      surface: scheme.surfaceContainerLow,
                      zero: colors.spoke,
                      track: colors.line,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(findingRange(finding, locale), style: small),
              Text(findingBasis(finding, habit), style: small),
            ],
          ),
        ),
      ],
    );
  }
}

// The range as a bar beside a zero tick, on a track scaled so both fit with
// room either side. The words above carry the numbers; this only shows how far
// the range sits from zero.
class _RangePainter extends CustomPainter {
  _RangePainter({
    required this.finding,
    required this.ink,
    required this.surface,
    required this.zero,
    required this.track,
  });

  final HabitFinding finding;
  final Color ink;
  final Color surface;
  final Color zero;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final double low = finding.interval.low, high = finding.interval.high;
    final double reach = <double>[
      low.abs(),
      high.abs(),
    ].reduce((a, b) => a > b ? a : b);
    if (reach == 0) return;
    double x(double v) => size.width / 2 + v / reach * (size.width / 2 - 6);
    final double mid = size.height / 2;
    canvas
      ..drawLine(
        Offset(0, mid),
        Offset(size.width, mid),
        Paint()
          ..color = track
          ..strokeWidth = 2,
      )
      ..drawLine(
        Offset(x(0), 0),
        Offset(x(0), size.height),
        Paint()
          ..color = zero
          ..strokeWidth = 2,
      )
      ..drawLine(
        Offset(x(low), mid),
        Offset(x(high), mid),
        Paint()
          ..color = ink
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(Offset(x(finding.effect), mid), 6, Paint()..color = ink)
      ..drawCircle(Offset(x(finding.effect), mid), 3, Paint()..color = surface);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.finding != finding ||
      old.ink != ink ||
      old.surface != surface ||
      old.zero != zero ||
      old.track != track;
}
