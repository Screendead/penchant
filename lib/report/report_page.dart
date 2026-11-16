import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/account/export_action.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/report/report_data.dart';
import 'package:tracker/report/report_output.dart';
import 'package:tracker/report/report_pdf.dart';
import 'package:tracker/widgets/dial_segments.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Settings › Report: which habits, how far back, and whether notes go in.
class ReportOptionsPage extends ConsumerStatefulWidget {
  const ReportOptionsPage({super.key, this.initialOptions});

  static const String route = '/settings/report';
  static const String title = 'Report';
  static const String settingsLabel = 'Make a report';
  static const String settingsValue = 'PDF';
  static const String intro =
      'A PDF to show a doctor, a counsellor or someone close: a calendar '
      'of each day’s total, each week’s total, the busiest hours and the '
      'most common tags. It is made on this device from your entries.';
  static const String notesLabel = 'Include notes';
  static const String notesSubtitle =
      'Notes on entries, day notes and tags in your own words';
  static const String make = 'Make report';
  static const String noHabits = 'Choose at least one habit.';
  static const String lockedHabit = 'Would not open on this device';
  static String failed(String reason) => "Couldn't make the report. $reason";

  // For tests and renders: the choices to start from.
  final ReportOptions? initialOptions;

  @override
  ConsumerState<ReportOptionsPage> createState() => _ReportOptionsPageState();
}

class _ReportOptionsPageState extends ConsumerState<ReportOptionsPage> {
  late ReportOptions _options =
      widget.initialOptions ?? const ReportOptions(viceIDs: <String>{});
  bool _making = false;

  void _toggle(String id, bool on) => setState(() {
    _options = _options.copyWith(
      viceIDs: on
          ? <String>{..._options.viceIDs, id}
          : (<String>{..._options.viceIDs}..remove(id)),
    );
  });

  Future<void> _make(int firstWeekday) async {
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _making = true);
    try {
      // From the server, as the export reads: offline it fails rather than
      // report from whatever the cache happens to hold.
      final AccountData data = await ref.read(accountProvider).fetchData();
      final ReportFonts fonts = await loadReportFonts();
      final ReportData report = buildReport(
        data,
        ReportOptions(
          viceIDs: _options.viceIDs,
          months: _options.months,
          includeNotes: _options.includeNotes,
          firstWeekday: firstWeekday,
        ),
        now: DateTime.now(),
      );
      final Uint8List pdf = await reportPdf(
        report,
        fonts,
        format: reportPaper(ui.PlatformDispatcher.instance.locale),
      );
      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              ReportPreviewPage(pdf: pdf, name: reportFileName(report.made)),
        ),
      );
    } catch (e, stack) {
      reportError(e, stack, context: 'while making a report');
      messenger.showSnackBar(
        SnackBar(content: Text(ReportOptionsPage.failed(authErrorMessage(e)))),
      );
    } finally {
      if (mounted) {
        setState(() => _making = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice> vices = ref.watch(viceListProvider).value ?? <Vice>[];
    final Map<String, HabitMark> marks = habitMarks(vices);
    final List<Vice> ordered = vices.toList()
      ..sort(
        (Vice a, Vice b) =>
            marks[a.id]!.creationIndex.compareTo(marks[b.id]!.creationIndex),
      );
    final DateTime today = ref.watch(todayProvider);
    final ReportWindow window = reportWindow(today, _options.months);
    final int firstIndex = MaterialLocalizations.of(
      context,
    ).firstDayOfWeekIndex;
    final bool ready = _options.viceIDs.isNotEmpty && !_making;
    return CardPage(
      title: ReportOptionsPage.title,
      children: <Widget>[
        const CardFoot(ReportOptionsPage.intro),
        const CardSectionLabel('Habits'),
        DialCard(
          top: 0,
          children: <Widget>[
            for (final Vice vice in ordered)
              _HabitChoice(
                vice: vice,
                selected: _options.viceIDs.contains(vice.id),
                onChanged: vice.locked || _making
                    ? null
                    : (bool on) => _toggle(vice.id, on),
              ),
          ],
        ),
        const CardSectionLabel('Period'),
        DialSegments<int>(
          choices: ReportOptions.monthChoices,
          selected: _options.months,
          label: (int months) => months == 1 ? '1 month' : '$months months',
          onChanged: (int months) =>
              setState(() => _options = _options.copyWith(months: months)),
        ),
        CardFoot(
          '${formatDate(window.start)} to '
          '${formatDate(addDays(window.end, -1))}, by calendar month.',
        ),
        DialCard(
          children: <Widget>[
            CardRow(
              label: ReportOptionsPage.notesLabel,
              subtitle: ReportOptionsPage.notesSubtitle,
              trailing: Switch.adaptive(
                value: _options.includeNotes,
                onChanged: _making
                    ? null
                    : (bool on) => setState(
                        () => _options = _options.copyWith(includeNotes: on),
                      ),
              ),
            ),
          ],
        ),
        const CardFoot(
          'Off, the report holds only amounts, times and the tags from '
          'Penchant’s list. Nothing from Apple Health is ever included.',
        ),
        const SizedBox(height: DialSpace.xl),
        FilledButton(
          onPressed: ready
              ? () => _make(firstIndex == 0 ? DateTime.sunday : firstIndex)
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(DialSize.circleButton + 12),
          ),
          child: _making
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(ReportOptionsPage.make),
        ),
        if (_options.viceIDs.isEmpty)
          const CardFoot(ReportOptionsPage.noHabits),
      ],
    );
  }
}

class _HabitChoice extends StatelessWidget {
  const _HabitChoice({
    required this.vice,
    required this.selected,
    required this.onChanged,
  });

  final Vice vice;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final String? note = vice.locked
        ? ReportOptionsPage.lockedHabit
        : vice.archived
        ? 'Archived'
        : null;
    return CardRow(
      label: vice.name,
      subtitle: note,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      trailing: Checkbox(
        value: selected && !vice.locked,
        onChanged: onChanged == null
            ? null
            : (bool? on) => onChanged!(on ?? false),
      ),
    );
  }
}

String reportFileName(DateTime made) =>
    'penchant-report-${made.toIso8601String().substring(0, 10)}.pdf';

/// The finished pages, the warning, then the share sheet.
class ReportPreviewPage extends ConsumerStatefulWidget {
  const ReportPreviewPage({super.key, required this.pdf, required this.name});

  static const String title = 'Your report';
  static const String warning =
      'Once you share this file it is outside Penchant’s encryption for '
      'good. Anyone who has a copy can read it, and it cannot be taken back.';
  static const String share = 'Share PDF';

  final Uint8List pdf;
  final String name;

  @override
  ConsumerState<ReportPreviewPage> createState() => _ReportPreviewPageState();
}

class _ReportPreviewPageState extends ConsumerState<ReportPreviewPage> {
  late final ReportOutput _output = ref.read(reportOutputProvider);
  late final Future<List<ui.Image>> _pages = _output.pages(widget.pdf);
  final GlobalKey _shareButton = GlobalKey();
  bool _sharing = false;

  @override
  void dispose() {
    _output.discard();
    super.dispose();
  }

  Future<void> _share() async {
    final Rect? origin = exportOrigin(_shareButton);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      final File file = await _output.write(widget.pdf, widget.name);
      await _output.share(file, origin: origin);
    } catch (e, stack) {
      reportError(e, stack, context: 'while sharing a report');
      messenger.showSnackBar(
        SnackBar(content: Text(ReportOptionsPage.failed(authErrorMessage(e)))),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    return CardPage(
      title: ReportPreviewPage.title,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: DialSpace.l),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(DialRadius.card),
              border: Border.all(color: colors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const StrokeIcon(DialGlyph.share, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ReportPreviewPage.warning,
                      style: TextStyle(
                        fontFamily: DialFonts.text,
                        fontSize: 14,
                        height: 1.4,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: DialSpace.l),
        FilledButton(
          key: _shareButton,
          onPressed: _sharing ? null : _share,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(DialSize.circleButton + 12),
          ),
          child: const Text(ReportPreviewPage.share),
        ),
        FutureBuilder<List<ui.Image>>(
          future: _pages,
          builder:
              (BuildContext context, AsyncSnapshot<List<ui.Image>> snapshot) {
                final List<ui.Image>? pages = snapshot.data;
                if (pages == null) {
                  return Padding(
                    padding: const EdgeInsets.all(DialSpace.xl),
                    child: Center(
                      child: snapshot.hasError
                          ? const Text('The pages could not be shown here.')
                          : const CircularProgressIndicator(),
                    ),
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final (int i, ui.Image page) in pages.indexed)
                      Padding(
                        padding: const EdgeInsets.only(top: DialSpace.l),
                        child: Semantics(
                          label: 'Page ${i + 1} of ${pages.length}',
                          image: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.line),
                              boxShadow: DialShadows.card(theme.brightness),
                            ),
                            child: AspectRatio(
                              aspectRatio: page.width / page.height,
                              child: RawImage(image: page, fit: BoxFit.fill),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
        ),
      ],
    );
  }
}
