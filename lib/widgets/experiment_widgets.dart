import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/insights/experiment_copy.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/settings_card.dart';

TextStyle _small(BuildContext context) =>
    DialTypeScale.bodyS.copyWith(color: DialColors.of(context).muted);

/// The finding card's "Test this for 6 weeks", an outlined pill with a "New"
/// tag, and the line under it.
class ExperimentButton extends StatelessWidget {
  const ExperimentButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
            side: BorderSide(color: scheme.outline),
            foregroundColor: scheme.onSurface,
            textStyle: DialTypeScale.body.copyWith(fontWeight: FontWeight.w600),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(ExperimentWords.button(experimentDefaultWeeks)),
              const SizedBox(width: DialSpace.xs),
              const ExcludeSemantics(child: _NewTag()),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(ExperimentWords.buttonNote, style: _small(context)),
      ],
    );
  }
}

class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.primary,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          ExperimentWords.newTag,
          style: DialTypeScale.label.copyWith(
            fontSize: 12,
            height: 16 / 12,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

/// Today's line above the dial while a plan runs: the day's rule and how far
/// along it is. Never on the Mac, which has no plan.
class ExperimentStrip extends StatelessWidget {
  const ExperimentStrip({
    super.key,
    required this.plan,
    required this.habit,
    required this.day,
    required this.locale,
    this.onTap,
  });

  final ExperimentPlan plan;
  final String habit;
  final DateTime day;
  final String locale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final ExperimentWords words = ExperimentWords(plan.metricId, locale);
    final int? index = plan.indexOf(day);
    final String title = words.stripTitle(
      habit,
      plan.noneOn(day),
      plan.fromHour,
    );
    final String line = words.stripLine(
      habit,
      index == null ? null : index + 1,
      plan.days,
    );
    final BorderRadius radius = BorderRadius.circular(18);
    return Padding(
      padding: const EdgeInsets.only(bottom: DialSpace.xs),
      child: Semantics(
        button: onTap != null,
        label: '$title. $line',
        excludeSemantics: true,
        child: Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: colors.line),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: DialTypeScale.body.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 20 / 15,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(line, style: _small(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: DialSpace.s),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surface2,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A finished plan's card under "Your experiment": the difference and its
/// range; when clear, the nights, the days kept and the old finding; when
/// not, "Can't tell" and the offer to run it on.
class ExperimentResultCard extends StatelessWidget {
  const ExperimentResultCard({
    super.key,
    required this.plan,
    required this.result,
    required this.habit,
    required this.mark,
    required this.locale,
    this.onRunOn,
    this.top = DialSpace.l,
  });

  final ExperimentPlan plan;
  final ExperimentResult result;
  final String habit;
  final HabitMark mark;
  final String locale;
  final VoidCallback? onRunOn;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle small = _small(context);
    final ExperimentWords words = ExperimentWords(plan.metricId, locale);
    final stats.Interval? interval = result.interval;
    return DialCard(
      top: top,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  HabitPip(mark: mark),
                  const SizedBox(width: DialSpace.xs),
                  Expanded(
                    child: Text(
                      words.header(habit, plan.end),
                      style: DialTypeScale.label.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (interval == null) ...<Widget>[
                Text(
                  ExperimentWords.tooFew,
                  style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: DialSpace.xs),
                Text(
                  words.basis(result, metricFloors[plan.metricId]?.family),
                  style: small,
                ),
              ] else ...<Widget>[
                Text(
                  words.sentence(habit, result, plan.fromHour),
                  style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: DialSpace.s),
                ExcludeSemantics(
                  child: SizedBox(
                    height: 14,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: ExperimentRangePainter(
                        effect: result.difference,
                        low: interval.low,
                        high: interval.high,
                        ink: scheme.onSurface,
                        surface: scheme.surfaceContainerLow,
                        zero: colors.spoke,
                        track: colors.line,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DialSpace.xs),
                Text(words.range(interval.low, interval.high), style: small),
                if (result.clear) ...<Widget>[
                  Text(
                    words.basis(result, metricFloors[plan.metricId]?.family),
                    style: small,
                  ),
                  Text(words.kept(habit, result, plan.fromHour), style: small),
                  const SizedBox(height: 10),
                  ExperimentDays(days: result.days),
                  const SizedBox(height: 4),
                  ExperimentLegend(habit: habit),
                  const SizedBox(height: 6),
                  Text(words.before(plan), style: small),
                ] else
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        onRunOn == null
                            ? words.shortBasis(result)
                            : '${words.shortBasis(result)} · ',
                        style: small,
                      ),
                      if (onRunOn != null)
                        Semantics(
                          button: true,
                          child: InkWell(
                            onTap: onRunOn,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  ExperimentWords.runOn,
                                  style: small.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                    decorationColor: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The planned days, two weeks a row: filled for "none", outlined for as
/// usual, hatched for a "none" day with the habit logged in its evening.
class ExperimentDays extends StatelessWidget {
  const ExperimentDays({super.key, required this.days});

  final List<ExperimentDay> days;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int from = 0; from < days.length; from += 14) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: from == 0 ? 0 : 4),
          child: Row(
            children: <Widget>[
              for (int i = from; i < from + 14; i++) ...<Widget>[
                if (i > from) const SizedBox(width: 4),
                Expanded(
                  child: i < days.length
                      ? _DayBox(kind: days[i])
                      : const SizedBox(height: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ExcludeSemantics(child: Column(children: rows));
  }
}

class _DayBox extends StatelessWidget {
  const _DayBox({required this.kind});

  final ExperimentDay? kind;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    return SizedBox(
      height: 12,
      width: 12,
      child: CustomPaint(
        painter: _DayBoxPainter(
          kind: kind,
          fill: scheme.primary,
          outline: scheme.outline,
          hatch: colors.data[1],
          hatchRim: colors.dataInk[1],
        ),
      ),
    );
  }
}

class _DayBoxPainter extends CustomPainter {
  _DayBoxPainter({
    required this.kind,
    required this.fill,
    required this.outline,
    required this.hatch,
    required this.hatchRim,
  });

  final ExperimentDay? kind;
  final Color fill;
  final Color outline;
  final Color hatch;
  final Color hatchRim;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect box = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(3),
    );
    switch (kind) {
      case ExperimentDay.none:
        canvas.drawRRect(box, Paint()..color = fill);
      case ExperimentDay.missed:
        canvas
          ..save()
          ..clipRRect(box);
        final Paint stripe = Paint()
          ..color = hatch
          ..strokeWidth = 2;
        for (double x = -size.height; x < size.width + size.height; x += 5) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            stripe,
          );
        }
        canvas.restore();
        canvas.drawRRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = hatchRim,
        );
      case ExperimentDay.usual || null:
        canvas.drawRRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = outline,
        );
    }
  }

  @override
  bool shouldRepaint(_DayBoxPainter old) =>
      old.kind != kind ||
      old.fill != fill ||
      old.outline != outline ||
      old.hatch != hatch ||
      old.hatchRim != hatchRim;
}

class ExperimentLegend extends StatelessWidget {
  const ExperimentLegend({super.key, required this.habit});

  final String habit;

  @override
  Widget build(BuildContext context) {
    final TextStyle small = _small(context);
    Widget item(ExperimentDay kind, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DayBox(kind: kind),
        const SizedBox(width: 6),
        Text(label, style: small),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      children: <Widget>[
        item(ExperimentDay.none, ExperimentWords.noneLegend),
        item(ExperimentDay.usual, ExperimentWords.usualLegend),
        item(ExperimentDay.missed, ExperimentWords.missedLegend(habit)),
      ],
    );
  }
}

/// The range as a bar beside a zero tick, as the finding cards draw theirs.
class ExperimentRangePainter extends CustomPainter {
  ExperimentRangePainter({
    required this.effect,
    required this.low,
    required this.high,
    required this.ink,
    required this.surface,
    required this.zero,
    required this.track,
  });

  final double effect;
  final double low;
  final double high;
  final Color ink;
  final Color surface;
  final Color zero;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
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
      ..drawCircle(Offset(x(effect), mid), 6, Paint()..color = ink)
      ..drawCircle(Offset(x(effect), mid), 3, Paint()..color = surface);
  }

  @override
  bool shouldRepaint(ExperimentRangePainter old) =>
      old.effect != effect ||
      old.low != low ||
      old.high != high ||
      old.ink != ink ||
      old.surface != surface ||
      old.zero != zero ||
      old.track != track;
}
