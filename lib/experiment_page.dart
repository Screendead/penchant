import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/insights/experiment_copy.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/experiment_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The plan screen: a new plan from a finding ([finding]), or the one
/// running ([running]), which can be stopped.
class ExperimentPage extends ConsumerStatefulWidget {
  const ExperimentPage.plan({
    super.key,
    required HabitFinding this.finding,
    required this.habit,
  }) : running = null;

  const ExperimentPage.running({
    super.key,
    required ExperimentPlan this.running,
    required this.habit,
  }) : finding = null;

  final HabitFinding? finding;
  final ExperimentPlan? running;
  final String habit;

  static Route<void> route(ExperimentPage page) => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => page,
  );

  @override
  ConsumerState<ExperimentPage> createState() => _ExperimentPageState();
}

class _ExperimentPageState extends ConsumerState<ExperimentPage> {
  int weeks = experimentDefaultWeeks;
  bool notify = false;
  int notifyMinutes = experimentDefaultNotifyMinutes;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.running?.notifyMinutes case final int minutes) {
      notify = true;
      notifyMinutes = minutes;
    }
  }

  String get metricId => widget.finding?.metricId ?? widget.running!.metricId;

  ExperimentPlan _draft(DateTime today) =>
      widget.running ??
      ExperimentPlan.start(
        widget.finding!,
        today: today,
        weeks: weeks,
        seed: 0,
        notifyMinutes: notify ? notifyMinutes : null,
      );

  Future<void> _toggleNotify(bool on) async {
    if (on) {
      final bool granted = await ref
          .read(experimentProvider.notifier)
          .askToNotify();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ExperimentWords.permissionDenied)),
        );
        return;
      }
    }
    setState(() => notify = on);
    if (widget.running != null) {
      await ref
          .read(experimentProvider.notifier)
          .setNotify(on ? notifyMinutes : null);
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: notifyMinutes ~/ 60,
        minute: notifyMinutes % 60,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => notifyMinutes = picked.hour * 60 + picked.minute);
    if (widget.running != null && notify) {
      await ref.read(experimentProvider.notifier).setNotify(notifyMinutes);
    }
  }

  Future<void> _start() async {
    setState(() => busy = true);
    final DateTime today = ref.read(todayProvider);
    await ref
        .read(experimentProvider.notifier)
        .start(
          ExperimentPlan.start(
            widget.finding!,
            today: today,
            weeks: weeks,
            seed: newExperimentSeed(),
            notifyMinutes: notify ? notifyMinutes : null,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stop() async {
    final bool? stop = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(ExperimentWords.stopTitle),
        content: const Text(ExperimentWords.stopBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(ExperimentWords.keepGoing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(ExperimentWords.stop),
          ),
        ],
      ),
    );
    if (stop != true || !mounted) return;
    await ref.read(experimentProvider.notifier).stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final ExperimentWords words = ExperimentWords(metricId, formatLocale);
    final DateTime today = ref.watch(todayProvider);
    final ExperimentPlan plan = _draft(today);
    final double? spread = widget.running == null
        ? ref.watch(experimentSpreadProvider(metricId))
        : null;
    final double finding = -plan.finding.effect;
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final TextStyle row = DialTypeScale.body.copyWith(color: scheme.onSurface);
    final TextStyle mono = DialTypeScale.monoL.copyWith(
      fontSize: 15,
      height: 21 / 15,
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
    );
    final ({String before, String after}) body = words.body(widget.habit);
    final int? index = plan.indexOf(today);

    Widget rowOf(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: row)),
          value,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        leadingWidth: 56,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: DialSpace.m),
          child: Center(
            child: CircleButton(
              icon: DialGlyph.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        titleSpacing: DialSpace.s,
        title: Text(
          words.title(widget.habit),
          style: DialTypeScale.displayM.copyWith(color: scheme.onSurface),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          DialSpace.gutter,
          0,
          DialSpace.gutter,
          50,
        ),
        children: <Widget>[
          DialCard(
            top: 0,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(text: body.before),
                          TextSpan(
                            text: words.rule(widget.habit, plan.fromHour),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: body.after),
                        ],
                      ),
                      style: row,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      words.bodyNote(widget.habit, plan.fromHour),
                      style: small,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.running == null) ...<Widget>[
            const _Section(ExperimentWords.howLong),
            Wrap(
              spacing: DialSpace.xs,
              runSpacing: DialSpace.xs,
              children: <Widget>[
                for (final int w in experimentLengths)
                  _LengthChip(
                    weeks: w,
                    selected: w == weeks,
                    plusMinus: spread == null
                        ? null
                        : words.plusMinus(expectedHalfWidth(spread, w)),
                    dim:
                        spread != null &&
                        expectedHalfWidth(spread, w) > finding.abs(),
                    onTap: () => setState(() => weeks = w),
                  ),
              ],
            ),
            const SizedBox(height: DialSpace.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                spread == null
                    ? ExperimentWords.noSpread
                    : words.spreadNote(
                        spread: spread,
                        finding: finding,
                        weeks: weeks,
                      ),
                style: small,
              ),
            ),
          ],
          const _Section(ExperimentWords.daysHeading),
          DialCard(
            top: 0,
            inset: 18,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: rowOf(
                  index == null ? ExperimentWords.starts : 'Today',
                  Text(
                    index == null
                        ? _startWords(plan.start, today)
                        : 'Day ${index + 1} of ${plan.days}',
                    style: row.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: rowOf(
                  ExperimentWords.ends,
                  Text(
                    DateFormat.MMMEd(formatLocale).format(plan.end),
                    style: row.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: rowOf(
                  ExperimentWords.noneDays,
                  Text(words.noneOf(plan), style: mono),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Text(
                  ExperimentWords.balance,
                  style: small.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          ),
          const _Section(ExperimentWords.tellMe),
          DialCard(
            top: 0,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 8, 2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(ExperimentWords.notification, style: row),
                    ),
                    Semantics(
                      button: true,
                      label: 'Notification time',
                      child: TextButton(
                        onPressed: _pickTime,
                        child: Text(
                          _clock(notifyMinutes),
                          style: mono.copyWith(
                            color: notify ? scheme.onSurface : colors.muted,
                          ),
                        ),
                      ),
                    ),
                    Switch(
                      value: notify,
                      onChanged: busy ? null : _toggleNotify,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Text(
                  ExperimentWords.notificationNote,
                  style: small.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: DialSpace.m),
          FilledButton(
            onPressed: busy
                ? null
                : widget.running == null
                ? _start
                : _stop,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              textStyle: DialTypeScale.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(
              widget.running == null
                  ? ExperimentWords.start
                  : ExperimentWords.stop,
            ),
          ),
        ],
      ),
    );
  }

  static String _startWords(DateTime start, DateTime today) {
    final String date = DateFormat.MMMd(formatLocale).format(start);
    return daysBetween(today, start) == 1 ? 'Tomorrow, $date' : date;
  }

  static String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, DialSpace.l, 6, 10),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: DialTypeScale.label.copyWith(
          fontSize: 12,
          height: 16 / 12,
          letterSpacing: 0.72,
          color: DialColors.of(context).muted,
        ),
      ),
    ),
  );
}

class _LengthChip extends StatelessWidget {
  const _LengthChip({
    required this.weeks,
    required this.selected,
    required this.plusMinus,
    required this.dim,
    required this.onTap,
  });

  final int weeks;
  final bool selected;
  final String? plusMinus;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color ink = selected ? scheme.onPrimary : scheme.onSurface;
    final String label = '$weeks weeks';
    return Opacity(
      opacity: dim && !selected ? 0.5 : 1,
      child: Semantics(
        selected: selected,
        button: true,
        label: plusMinus == null ? label : '$label, plus or minus ${plusMinus!.substring(1)}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: ShapeDecoration(
                  color: selected ? scheme.primary : null,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: DialTypeScale.body.copyWith(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                    if (plusMinus != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        plusMinus!,
                        style: DialTypeScale.monoL.copyWith(
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          color: ink.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
