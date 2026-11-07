import 'dart:async';

import 'package:clock/clock.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/onboarding/presets.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

enum OnboardingStep { intro, picker, disclaimer, firstLog }

// First run for an account with no habits: what the app is, the presets,
// the disclaimer, and an optional first log. [onDone] lands on Today.
class Onboarding extends ConsumerStatefulWidget {
  const Onboarding({
    super.key,
    required this.onDone,
    this.initialStep = OnboardingStep.intro,
    this.initialSelection = const <String>{},
  });

  final VoidCallback onDone;
  final OnboardingStep initialStep;
  final Set<String> initialSelection;

  static const Key skipKey = ValueKey<String>('onboarding-skip');
  static Key logKey(String habitName) =>
      ValueKey<String>('onboarding-log-$habitName');

  @override
  ConsumerState<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<Onboarding> {
  late OnboardingStep step = widget.initialStep;
  late final Set<String> selected = <String>{...widget.initialSelection};
  final Map<String, int> quantities = <String, int>{};
  final Set<String> logged = <String>{};
  bool created = false;

  void _go(OnboardingStep next) => setState(() => step = next);

  // The habits a first log can go to: those already made, oldest first.
  List<Vice> get _habits => <Vice>[
    ...?ref.watch(unarchivedViceListProvider).value?.reversed,
  ];

  Future<void> _settleAll(
    List<(SentWrite, String)> sent,
    String doing,
    ScaffoldMessengerState messenger,
  ) async {
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    try {
      final List<bool> synced = await Future.wait(<Future<bool>>[
        for (final (SentWrite write, String what) in sent)
          rejected.settle(write, what),
      ]);
      if (synced.contains(false) && messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text(queuedMessage)));
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: doing);
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Not saved. ${firestoreErrorMessage(e)}')),
        );
      }
    }
  }

  // The writes are on the device at once, so the flow moves on without
  // waiting up to settleWrite's ten seconds for the server.
  void _createPicked() {
    final User? user = ref.read(userProvider).value;
    // A second tap before the rebuild would create every pick again.
    if (user == null || step != OnboardingStep.picker) {
      return;
    }
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final Set<String> existing = <String>{
      for (final Vice v in ref.read(viceListProvider).value ?? const <Vice>[])
        v.name,
    };
    final List<(SentWrite, String)> sent = <(SentWrite, String)>[
      for (final HabitPreset p in habitPresets)
        if (selected.contains(p.name) && !existing.contains(p.name))
          (
            writes.addVice(
              ownerID: user.uid,
              name: p.name,
              unit: p.unit,
              category: guessCategory(p.name),
            ),
            'Not saved: the habit ${p.name}',
          ),
    ];
    created = sent.isNotEmpty;
    unawaited(
      _settleAll(sent, 'while saving a habit', ScaffoldMessenger.of(context)),
    );
    _go(OnboardingStep.disclaimer);
  }

  void _log(Vice vice) {
    final User? user = ref.read(userProvider).value;
    if (user == null || logged.contains(vice.id)) {
      return;
    }
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final int quantity = quantities[vice.id] ?? 1;
    final DateTime at = clock.now();
    final SentWrite write = writes.recordActivity(
      writes.newActivityID(),
      ownerID: user.uid,
      viceID: vice.id,
      quantity: quantity,
      createdAt: at,
    );
    setState(() => logged.add(vice.id));
    final String entry = describeActivity(
      vice.name,
      vice.unit,
      quantity,
      at,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    unawaited(
      _settleAll(
        <(SentWrite, String)>[(write, 'Not saved: $entry')],
        'while logging a first entry',
        ScaffoldMessenger.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice> habits = _habits;
    return switch (step) {
      OnboardingStep.intro => _Frame(
        step: 1,
        onSkip: () => _go(OnboardingStep.disclaimer),
        body: const _Intro(),
        actions: <Widget>[
          FilledButton(
            onPressed: () => _go(OnboardingStep.picker),
            child: const Text(OnboardingCopy.start),
          ),
        ],
      ),
      OnboardingStep.picker => _Frame(
        step: 2,
        onSkip: () => _go(OnboardingStep.disclaimer),
        body: _Picker(
          selected: selected,
          onToggle: (String name) => setState(() {
            if (!selected.remove(name)) {
              selected.add(name);
            }
          }),
          onSomethingElse: () => Navigator.of(context).pushNamed('/vices/add'),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: selected.isEmpty && habits.isEmpty
                ? null
                : _createPicked,
            child: Text(
              selected.isEmpty
                  ? OnboardingCopy.continueLabel
                  : OnboardingCopy.continueWith(selected.length),
            ),
          ),
        ],
      ),
      OnboardingStep.disclaimer => _Frame(
        step: 3,
        body: const _Disclaimer(),
        actions: <Widget>[
          FilledButton(
            onPressed: () => habits.isEmpty && !created
                ? widget.onDone()
                : _go(OnboardingStep.firstLog),
            child: const Text(OnboardingCopy.acknowledge),
          ),
        ],
      ),
      OnboardingStep.firstLog => _Frame(
        step: 4,
        body: _FirstLog(
          habits: habits,
          quantities: quantities,
          logged: logged,
          onChange: (Vice vice, int quantity) =>
              setState(() => quantities[vice.id] = quantity),
          onLog: _log,
        ),
        actions: <Widget>[
          if (logged.isEmpty)
            OutlinedButton(
              onPressed: widget.onDone,
              child: const Text(OnboardingCopy.notNow),
            )
          else
            FilledButton(
              onPressed: widget.onDone,
              child: const Text(OnboardingCopy.toToday),
            ),
        ],
      ),
    };
  }
}

const int _steps = 4;

TextStyle _heading(BuildContext context) => DialTypeScale.displayL.copyWith(
  color: Theme.of(context).colorScheme.onSurface,
);

TextStyle _muted(BuildContext context, [TextStyle? style]) =>
    (style ?? DialTypeScale.body).copyWith(color: DialColors.of(context).muted);

class _Frame extends StatelessWidget {
  const _Frame({
    required this.step,
    required this.body,
    required this.actions,
    this.onSkip,
  });

  // 1-based.
  final int step;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DialSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: DialSize.pillHeight,
                child: Row(
                  children: <Widget>[
                    Semantics(
                      label: 'Step $step of $_steps',
                      child: ExcludeSemantics(
                        child: Row(
                          children: <Widget>[
                            for (int i = 1; i <= _steps; i++)
                              AnimatedContainer(
                                duration: DialMotion.reducedFade,
                                width: i == step ? 20 : 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: i <= step
                                      ? scheme.primary
                                      : scheme.outline,
                                  borderRadius: BorderRadius.circular(
                                    DialRadius.pill,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (onSkip != null)
                      TextButton(
                        key: Onboarding.skipKey,
                        onPressed: onSkip,
                        child: const Text(OnboardingCopy.skip),
                      ),
                  ],
                ),
              ),
              Expanded(child: body),
              const SizedBox(height: DialSpace.s),
              ...actions,
              const SizedBox(height: DialSpace.m),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);

    return ListView(
      children: <Widget>[
        const SizedBox(height: DialSpace.xxxl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.surface2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              size: 34,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: Text(
            OnboardingCopy.introHeadline,
            style: DialTypeScale.displayXL.copyWith(color: scheme.onSurface),
          ),
        ),
        const SizedBox(height: DialSpace.s),
        Text(
          OnboardingCopy.introBody,
          style: _muted(context, DialTypeScale.bodyL),
        ),
        const SizedBox(height: DialSpace.xxl),
        for (final (IconData icon, String text) in OnboardingCopy.introPoints)
          Padding(
            padding: const EdgeInsets.only(bottom: DialSpace.m),
            child: Row(
              children: <Widget>[
                Icon(icon, color: scheme.onSurface),
                const SizedBox(width: DialSpace.m),
                Expanded(
                  child: Text(
                    text,
                    style: DialTypeScale.bodyL.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.selected,
    required this.onToggle,
    required this.onSomethingElse,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onSomethingElse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 10;
        final double tile = (constraints.maxWidth - gap) / 2;
        return ListView(
          padding: const EdgeInsets.only(top: DialSpace.xs),
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(OnboardingCopy.question, style: _heading(context)),
            ),
            const SizedBox(height: DialSpace.xs),
            Text(OnboardingCopy.pickerHint, style: _muted(context)),
            const SizedBox(height: DialSpace.l),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final HabitPreset preset in habitPresets)
                  SizedBox(
                    width: tile,
                    child: PresetTile(
                      icon: preset.icon,
                      title: preset.name,
                      subtitle: OnboardingCopy.countedIn(preset.unit),
                      selected: selected.contains(preset.name),
                      onTap: () => onToggle(preset.name),
                    ),
                  ),
                SizedBox(
                  width: tile,
                  child: PresetTile(
                    icon: Icons.add,
                    title: OnboardingCopy.somethingElse,
                    subtitle: OnboardingCopy.somethingElseHint,
                    onTap: onSomethingElse,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DialSpace.m),
          ],
        );
      },
    );
  }
}

// A preset to pick: selection is ink, as the theme's selected chips are.
class PresetTile extends StatelessWidget {
  const PresetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  // Null for a tile that is an action rather than a choice.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool on = selected ?? false;
    final Color foreground = on ? scheme.onPrimary : scheme.onSurface;
    final BorderRadius radius = BorderRadius.circular(DialRadius.tile);

    return Semantics(
      selected: selected,
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: on ? null : DialShadows.card(theme.brightness),
        ),
        child: Material(
          color: on ? scheme.primary : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: on ? scheme.primary : colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(icon, color: foreground),
                        const Spacer(),
                        if (on)
                          Icon(Icons.check_circle, size: 20, color: foreground),
                      ],
                    ),
                    const SizedBox(height: DialSpace.xxs),
                    Text(
                      title,
                      style: DialTypeScale.label.copyWith(color: foreground),
                    ),
                    Text(
                      subtitle,
                      style: DialTypeScale.bodyS.copyWith(
                        color: on ? scheme.onPrimary : colors.muted,
                      ),
                    ),
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

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListView(
      children: <Widget>[
        const SizedBox(height: DialSpace.xxxl * 2),
        Icon(Icons.info_outline, size: 40, color: scheme.onSurface),
        const SizedBox(height: DialSpace.l),
        Semantics(
          header: true,
          child: Text(OnboardingCopy.disclaimerTitle, style: _heading(context)),
        ),
        const SizedBox(height: DialSpace.m),
        Text(
          OnboardingCopy.disclaimer,
          style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: DialSpace.m),
        Text(OnboardingCopy.privacy, style: _muted(context)),
      ],
    );
  }
}

class _FirstLog extends StatelessWidget {
  const _FirstLog({
    required this.habits,
    required this.quantities,
    required this.logged,
    required this.onChange,
    required this.onLog,
  });

  final List<Vice> habits;
  final Map<String, int> quantities;
  final Set<String> logged;
  final void Function(Vice vice, int quantity) onChange;
  final ValueChanged<Vice> onLog;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);

    return ListView(
      padding: const EdgeInsets.only(top: DialSpace.xs),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(OnboardingCopy.firstLogTitle, style: _heading(context)),
        ),
        const SizedBox(height: DialSpace.xs),
        Text(OnboardingCopy.firstLogBody, style: _muted(context)),
        const SizedBox(height: DialSpace.xl),
        for (final Vice vice in habits)
          Padding(
            padding: const EdgeInsets.only(bottom: DialSpace.s),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(DialRadius.tile),
                border: Border.all(color: colors.line),
                boxShadow: DialShadows.card(theme.brightness),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                child: _FirstLogRow(
                  vice: vice,
                  quantity: quantities[vice.id] ?? 1,
                  logged: logged.contains(vice.id),
                  onChange: (int q) => onChange(vice, q),
                  onLog: () => onLog(vice),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FirstLogRow extends StatelessWidget {
  const _FirstLogRow({
    required this.vice,
    required this.quantity,
    required this.logged,
    required this.onChange,
    required this.onLog,
  });

  final Vice vice;
  final int quantity;
  final bool logged;
  final ValueChanged<int> onChange;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);

    final IconData? icon = presetIcon(vice.name);
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, color: scheme.onSurface),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                vice.name,
                style: DialTypeScale.label.copyWith(color: scheme.onSurface),
              ),
              Text(
                vice.unit.label(quantity),
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        if (logged)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DialSpace.s),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.check, size: 20, color: scheme.onSurface),
                const SizedBox(width: DialSpace.xxs),
                Text(
                  OnboardingCopy.logged,
                  style: DialTypeScale.label.copyWith(color: scheme.onSurface),
                ),
              ],
            ),
          )
        else ...<Widget>[
          IconButton(
            tooltip: 'Less ${vice.name}',
            onPressed: quantity > 1 ? () => onChange(quantity - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'More ${vice.name}',
            onPressed: () => onChange(quantity + 1),
            icon: const Icon(Icons.add),
          ),
          FilledButton(
            key: Onboarding.logKey(vice.name),
            onPressed: onLog,
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, DialSize.minTapTarget),
            ),
            child: Text(
              OnboardingCopy.log,
              semanticsLabel:
                  'Log ${vice.unit.label(quantity)} of ${vice.name}',
            ),
          ),
        ],
      ],
    );
  }
}
