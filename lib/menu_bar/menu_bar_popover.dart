import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/appearance_provider.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/app_menu_bar.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/penchant_mark.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';

// Shared with macos/Runner/StatusItemController.swift.
const MethodChannel menuBarChannel = MethodChannel('penchant/menu_bar');

// r10-widget-undo B: a log from outside the main window has a 5-second Undo.
const Duration menuBarUndoWindow = Duration(seconds: 5);

/// The popover under the macOS status item: today's dial above the habits,
/// and a click on a habit logs one of it now. It runs in its own Flutter view
/// on the main window's engine, so it shares every provider with the app.
class MenuBarPopover extends ConsumerWidget {
  const MenuBarPopover({
    super.key,
    required this.started,
    this.openApp = openMainWindow,
  });

  static const String signedOut = 'Sign in to Penchant to log from here.';
  static const String noHabits = 'No habits yet. Add one in Penchant.';
  static const String openLabel = 'Open Penchant';

  // True once Firebase has started; no provider may be read before.
  final ValueListenable<bool> started;
  final VoidCallback openApp;

  static void openMainWindow() =>
      menuBarChannel.invokeMethod<void>('openMainWindow');

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ValueListenableBuilder<bool>(
        valueListenable: started,
        builder: (BuildContext context, bool ready, _) => MaterialApp(
          title: 'Penchant',
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: ready ? ref.watch(appearanceProvider) : ThemeMode.system,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: appLocales,
          localeListResolutionCallback: resolveAppLocale,
          home: Scaffold(
            body: ready
                ? _PopoverBody(openApp: openApp)
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
}

class _PopoverBody extends ConsumerStatefulWidget {
  const _PopoverBody({required this.openApp});

  final VoidCallback openApp;

  @override
  ConsumerState<_PopoverBody> createState() => _PopoverBodyState();
}

class _PopoverBodyState extends ConsumerState<_PopoverBody> {
  late final TodayLogTarget _logTarget = ref.read(todayLogTargetProvider);

  @override
  void initState() {
    super.initState();
    // While the popover is open, Cmd-1 to Cmd-9 log here, where the Undo is.
    _logTarget.add(_log);
  }

  @override
  void dispose() {
    _logTarget.remove(_log);
    super.dispose();
  }

  void _log(Vice vice) {
    logOne(
      ref,
      ScaffoldMessenger.of(context),
      vice,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      undoWindow: menuBarUndoWindow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(userProvider).value;
    final Widget header = _Header(openApp: widget.openApp);
    if (user == null) {
      return Column(
        children: <Widget>[
          header,
          const Expanded(child: InfoBox(message: MenuBarPopover.signedOut)),
        ],
      );
    }

    final DateTime today = ref.watch(todayProvider);
    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final List<Vice>? allVices = ref.watch(viceListProvider).value;
    final AsyncValue<List<ViceActivity>> activitiesValue = ref.watch(
      viceActivityDayProvider(today),
    );
    final List<Vice>? listed = vicesValue.value;

    final Widget body;
    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      body = InfoBox(
        message: loadErrorMessage('today', error),
        isError: true,
        onRetry: () {
          ref.invalidate(viceListForUserProvider, asReload: true);
          ref.invalidate(viceActivityDayForUserProvider, asReload: true);
        },
      );
    } else if (listed != null && listed.isEmpty) {
      body = const InfoBox(message: MenuBarPopover.noHabits);
    } else {
      final Map<String, HabitMark> marks = habitMarks(
        allVices ?? listed ?? const <Vice>[],
      );
      HabitMark markOf(Vice vice) => marks[vice.id] ?? const HabitMark(0);
      final List<Vice>? vices = listed == null
          ? null
          : tallyOrder(listed, marks);
      final List<ViceActivity>? activities = activitiesValue.value;
      final List<DialEntry>? entries = vices == null || activities == null
          ? null
          : dialEntries(vices, activities, markOf);
      final Map<String, num> totals = dayTotals(
        vices ?? const <Vice>[],
        entries ?? const <DialEntry>[],
      );
      body = _Today(
        today: today,
        vices: vices,
        entries: entries,
        totals: totals,
        markOf: markOf,
        onLog: _log,
      );
    }

    return Column(
      children: <Widget>[
        header,
        Expanded(child: body),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.openApp});

  final VoidCallback openApp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DialSpace.m, 10, 6, 0),
      child: Row(
        children: <Widget>[
          const PenchantMark(size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Penchant',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: openApp,
            child: const Text(MenuBarPopover.openLabel),
          ),
        ],
      ),
    );
  }
}

class _Today extends ConsumerWidget {
  const _Today({
    required this.today,
    required this.vices,
    required this.entries,
    required this.totals,
    required this.markOf,
    required this.onLog,
  });

  // The popover is about 340 pt wide; the dial leaves the habits room below.
  static const double dialSide = 232;

  final DateTime today;
  final List<Vice>? vices;
  final List<DialEntry>? entries;
  final Map<String, num> totals;
  final HabitMark Function(Vice vice) markOf;
  final void Function(Vice vice) onLog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vice>? vices = this.vices;
    final List<DialEntry>? entries = this.entries;
    final bool offline = ref.watch(offlineProvider).value ?? false;
    final String? summary = vices == null || entries == null
        ? null
        : DayDial.summary(
            today,
            today,
            vices,
            <num>[for (final Vice v in vices) totals[v.id]!],
            <DateTime>[for (final DialEntry e in entries) e.at],
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        for (final (int i, Vice vice) in (vices ?? const <Vice>[]).indexed.take(
          habitKeyCount,
        ))
          habitKey(i): () => onLog(vice),
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        debugLabel: 'Menu bar popover',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            DialSpace.xs,
            DialSpace.xs,
            DialSpace.xs,
            DialSpace.m,
          ),
          children: <Widget>[
            Center(
              child: SizedBox.square(
                dimension: dialSide,
                child: DayDial(
                  day: today,
                  today: today,
                  entries: entries,
                  semanticsLabel: summary,
                  offline: offline,
                  storedTypicals: ref.watch(storedTypicalsProvider),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (vices == null)
              const Padding(
                padding: EdgeInsets.all(DialSpace.m),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final Vice vice in vices)
                MenuBarHabitRow(
                  key: ValueKey<String>('menu-bar-${vice.id}'),
                  vice: vice,
                  mark: markOf(vice),
                  total: entries == null ? null : totals[vice.id],
                  day: today,
                  onLog: () => onLog(vice),
                ),
          ],
        ),
      ),
    );
  }
}

/// A habit in the popover: Today's tally row, and a click anywhere on it logs
/// one, as its + does.
class MenuBarHabitRow extends StatelessWidget {
  const MenuBarHabitRow({
    super.key,
    required this.vice,
    required this.mark,
    required this.total,
    required this.day,
    required this.onLog,
  });

  final Vice vice;
  final HabitMark mark;
  final num? total;
  final DateTime day;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onLog,
      borderRadius: BorderRadius.circular(14),
      child: TallyRow(
        vice: vice,
        mark: mark,
        total: total,
        day: day,
        onLog: (_) => onLog(),
      ),
    ),
  );
}
