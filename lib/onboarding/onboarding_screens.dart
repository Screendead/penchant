import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/onboarding/onboarding_variant.dart';

const int onboardingSteps = 4;

class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({
    super.key,
    required this.step,
    required this.body,
    required this.actions,
    this.onSkip,
  });

  /// 1-based.
  final int step;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    for (int i = 1; i <= onboardingSteps; i++)
                      Container(
                        width: i == step ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: i <= step
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const Spacer(),
                    if (onSkip != null)
                      TextButton(onPressed: onSkip, child: const Text('Skip')),
                  ],
                ),
              ),
              Expanded(child: body),
              const SizedBox(height: 12),
              ...actions,
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key, required this.variant, this.onStart});

  final OnboardingVariant variant;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return OnboardingFrame(
      step: 1,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.auto_stories_outlined,
              size: 36,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 28),
          Text(variant.introHeadline, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            variant.introBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          for (final (IconData icon, String text) in variant.introPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: onStart ?? () {},
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: const Text('Start'),
        ),
      ],
    );
  }
}

class PresetPickerScreen extends StatefulWidget {
  const PresetPickerScreen({
    super.key,
    required this.variant,
    this.initialSelection = const {},
    this.onContinue,
  });

  final OnboardingVariant variant;
  final Set<String> initialSelection;
  final ValueChanged<List<VicePreset>>? onContinue;

  @override
  State<PresetPickerScreen> createState() => _PresetPickerScreenState();
}

class _PresetPickerScreenState extends State<PresetPickerScreen> {
  late final Set<String> selected = {...widget.initialSelection};

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<VicePreset> presets = widget.variant.presets;

    return OnboardingFrame(
      step: 2,
      onSkip: () {},
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.variant.question,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.variant.pickerHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.05,
            children: [
              for (final VicePreset preset in presets)
                _PresetTile(
                  icon: preset.icon,
                  title: preset.name,
                  subtitle: 'Counted in ${preset.unit.plural}',
                  selected: selected.contains(preset.name),
                  onTap: () => setState(() {
                    if (!selected.remove(preset.name)) {
                      selected.add(preset.name);
                    }
                  }),
                ),
              _PresetTile(
                icon: Icons.add,
                title: 'Something else',
                subtitle: 'Name it yourself',
                selected: false,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => widget.onContinue?.call([
                  for (final VicePreset p in presets)
                    if (selected.contains(p.name)) p,
                ]),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: Text(
            selected.isEmpty ? 'Continue' : 'Continue with ${selected.length}',
          ),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurface;

    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: foreground),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle, size: 20, color: colors.primary),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: foreground),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NameYourOwnScreen extends StatefulWidget {
  const NameYourOwnScreen({
    super.key,
    required this.variant,
    this.initialName = '',
    this.initialUnit,
  });

  final OnboardingVariant variant;
  final String initialName;
  final Unit? initialUnit;

  @override
  State<NameYourOwnScreen> createState() => _NameYourOwnScreenState();
}

class _NameYourOwnScreenState extends State<NameYourOwnScreen> {
  late final TextEditingController name = TextEditingController(
    text: widget.initialName,
  );
  late Unit? unit = widget.initialUnit;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Unit? chosen = unit;

    return OnboardingFrame(
      step: 2,
      onSkip: () {},
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          Text(widget.variant.question, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            widget.variant.pickerHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              floatingLabelAlignment: FloatingLabelAlignment.start,
            ),
          ),
          const SizedBox(height: 24),
          Text('How do you count it?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final Unit u in Unit.values)
                ChoiceChip(
                  label: Text(u.plural),
                  selected: u == chosen,
                  onSelected: (_) => setState(() => unit = u),
                ),
            ],
          ),
          if (chosen != null) ...[
            const SizedBox(height: 16),
            Text(
              'You\'ll log it as ${chosen.label(1)}, ${chosen.label(2)}, '
              'and so on.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Add another'),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: name.text.isEmpty || chosen == null ? null : () {},
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key, required this.variant});

  final OnboardingVariant variant;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return OnboardingFrame(
      step: 3,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text(variant.disclaimerTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(OnboardingVariant.disclaimer, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Text(
            'Your entries are private to your account. You can export or '
            'delete them at any time from Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () {},
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: Text(variant.acknowledge),
        ),
      ],
    );
  }
}

class FirstLogScreen extends StatefulWidget {
  const FirstLogScreen({
    super.key,
    required this.variant,
    required this.entries,
  });

  final OnboardingVariant variant;
  final List<VicePreset> entries;

  @override
  State<FirstLogScreen> createState() => _FirstLogScreenState();
}

class _FirstLogScreenState extends State<FirstLogScreen> {
  late final List<int> quantities = [for (final _ in widget.entries) 1];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return OnboardingFrame(
      step: 4,
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          Text(
            widget.variant.firstLogTitle,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            widget.variant.firstLogBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < widget.entries.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: colors.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(widget.entries[i].icon, color: colors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.entries[i].name,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            widget.entries[i].unit.label(quantities[i]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Less',
                      onPressed: quantities[i] > 1
                          ? () => setState(() => quantities[i]--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: 'More',
                      onPressed: () => setState(() => quantities[i]++),
                      icon: const Icon(Icons.add),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonal(
                      onPressed: () {},
                      child: const Text('Log'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () {},
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          child: const Text('Not now, go to Today'),
        ),
      ],
    );
  }
}
