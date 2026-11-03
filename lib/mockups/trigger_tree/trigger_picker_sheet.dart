import 'package:flutter/material.dart';
import 'package:tracker/mockups/trigger_tree/trigger_tree.dart';

/// The detail sheet shown after a one-tap log: optional triggers from a tree,
/// one-tap chips for this vice's usual ones, and free text at any level.
class TriggerPickerSheet extends StatefulWidget {
  const TriggerPickerSheet({
    super.key,
    required this.tree,
    required this.entryLabel,
    required this.viceName,
    this.recent = const <String>[],
    this.customLabels = const <String, String>{},
    this.initialRoot,
    this.initialSelected = const <String>{},
    this.initialFreeText = '',
    this.suggestion,
    this.suggestionCount = 3,
    this.onDone,
  });

  final TriggerTree tree;
  final String entryLabel;
  final String viceName;

  /// Ranked paths for this vice, most likely first.
  final List<String> recent;
  final Map<String, String> customLabels;
  final String? initialRoot;
  final Set<String> initialSelected;
  final String initialFreeText;

  /// A custom path used often enough to offer as a permanent node.
  final String? suggestion;
  final int suggestionCount;
  final ValueChanged<Set<String>>? onDone;

  @override
  State<TriggerPickerSheet> createState() => _TriggerPickerSheetState();
}

class _TriggerPickerSheetState extends State<TriggerPickerSheet> {
  late String? root = widget.initialRoot;
  late final Set<String> selected = <String>{...widget.initialSelected};
  late final Map<String, String> customLabels = <String, String>{
    ...widget.customLabels,
  };
  late final TextEditingController freeText = TextEditingController(
    text: widget.initialFreeText,
  );
  final FocusNode freeTextFocus = FocusNode();
  late bool showRootFreeText = widget.initialFreeText.isNotEmpty;
  late String? suggestion = widget.suggestion;

  String labelFor(String path) {
    final String? custom = customLabels[path];

    if (custom != null) {
      return custom;
    }

    return widget.tree.labels(path)?.join(TriggerTree.separator) ?? path;
  }

  void openRoot(String id) {
    setState(() {
      root = id;

      if (!selected.any((p) => p == id || p.startsWith('$id/'))) {
        selected.add(id);
      }
    });
  }

  void toggleChild(String parent, String path) {
    setState(() {
      if (!selected.remove(path)) {
        selected
          ..remove(parent)
          ..add(path);
      }
    });
  }

  int pickedUnder(String id) =>
      selected.where((p) => p == id || p.startsWith('$id/')).length;

  void openRootFreeText() {
    setState(() => showRootFreeText = true);
    freeTextFocus.requestFocus();
  }

  void toggle(String path) {
    setState(() {
      if (!selected.remove(path)) {
        selected.add(path);
      }
    });
  }

  void addFreeText() {
    final String label = freeText.text.trim();

    if (label.isEmpty) {
      return;
    }

    final String slug = label.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]+'),
      '-',
    );
    final String path = root == null
        ? '${TriggerTree.customPrefix}/$slug'
        : '$root/${TriggerTree.customPrefix}-$slug';

    setState(() {
      customLabels[path] = root == null
          ? label
          : '${widget.tree.root(root!)!.label}${TriggerTree.separator}$label';
      selected
        ..remove(root)
        ..add(path);
      freeText.clear();
    });
  }

  @override
  void dispose() {
    freeText.dispose();
    freeTextFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final TriggerNode? openNode = root == null ? null : widget.tree.root(root!);

    return Material(
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _Header(entryLabel: widget.entryLabel),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: openNode == null
                    ? _levelOne(theme)
                    : _levelTwo(theme, openNode),
              ),
            ),
            _Footer(
              selected: selected.toList(),
              labelFor: labelFor,
              onRemove: toggle,
              onDone: () => widget.onDone?.call(selected),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _levelOne(ThemeData theme) {
    final List<TriggerNode> roots = widget.tree.roots;

    return <Widget>[
      if (widget.recent.isNotEmpty) ...[
        _SectionLabel('Usual for ${widget.viceName}'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final String path in widget.recent)
              FilterChip(
                label: Text(labelFor(path)),
                selected: selected.contains(path),
                onSelected: (_) => toggle(path),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (suggestion != null) ...[
        _Suggestion(
          label: labelFor(suggestion!),
          count: widget.suggestionCount,
          onKeep: () => setState(() => suggestion = null),
          onDismiss: () => setState(() => suggestion = null),
        ),
        const SizedBox(height: 16),
      ],
      _SectionLabel(widget.recent.isEmpty ? widget.tree.prompt : 'Or browse'),
      // Once this vice has usual triggers, the tree shrinks to a row of chips
      // so the one-tap row stays the first thing seen.
      if (widget.recent.isEmpty)
        GridView.count(
          crossAxisCount: 2,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3.5,
          children: [
            for (final TriggerNode node in roots)
              _RootTile(
                icon: node.icon ?? Icons.label_outline,
                label: node.label,
                picked: pickedUnder(node.id),
                onTap: () => openRoot(node.id),
              ),
            _RootTile(
              icon: Icons.edit_outlined,
              label: 'Your own',
              picked: 0,
              drills: false,
              onTap: openRootFreeText,
            ),
          ],
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final TriggerNode node in roots)
              ActionChip(
                avatar: Icon(node.icon ?? Icons.label_outline),
                label: Text(node.label),
                backgroundColor: pickedUnder(node.id) > 0
                    ? theme.colorScheme.secondaryContainer
                    : null,
                onPressed: () => openRoot(node.id),
              ),
            ActionChip(
              avatar: const Icon(Icons.edit_outlined),
              label: const Text('Your own'),
              onPressed: openRootFreeText,
            ),
          ],
        ),
      if (showRootFreeText) ...[
        const SizedBox(height: 16),
        _FreeTextField(
          controller: freeText,
          focusNode: freeTextFocus,
          hint: 'In your own words',
          onSubmit: addFreeText,
        ),
      ],
    ];
  }

  List<Widget> _levelTwo(ThemeData theme, TriggerNode node) {
    final ColorScheme colors = theme.colorScheme;

    return <Widget>[
      Row(
        children: [
          IconButton(
            tooltip: 'All areas',
            onPressed: () => setState(() => root = null),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Icon(node.icon, color: colors.primary),
          const SizedBox(width: 8),
          Text(node.label, style: theme.textTheme.titleLarge),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        child: Text(
          'Pick one to be more specific, or leave it at "${node.label}".',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final TriggerNode child in node.children)
              FilterChip(
                label: Text(child.label),
                selected: selected.contains('${node.id}/${child.id}'),
                onSelected: (_) =>
                    toggleChild(node.id, '${node.id}/${child.id}'),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _FreeTextField(
          controller: freeText,
          focusNode: freeTextFocus,
          hint: 'Something else, in your own words',
          onSubmit: addFreeText,
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entryLabel});

  final String entryLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'Saved · $entryLabel',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('What was going on?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Optional. Tap any that fit.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _RootTile extends StatelessWidget {
  const _RootTile({
    required this.icon,
    required this.label,
    required this.picked,
    required this.onTap,
    this.drills = true,
  });

  final IconData icon;
  final String label;
  final int picked;
  final VoidCallback onTap;
  final bool drills;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool active = picked > 0;
    final Color foreground = active
        ? colors.onSecondaryContainer
        : colors.onSurface;

    return Material(
      color: active
          ? colors.secondaryContainer
          : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$picked',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              if (drills)
                Icon(Icons.chevron_right, size: 20, color: foreground)
              else
                Icon(Icons.add, size: 20, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeTextField extends StatelessWidget {
  const _FreeTextField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.edit_outlined),
        suffixIcon: IconButton(
          tooltip: 'Add',
          onPressed: onSubmit,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.label,
    required this.count,
    required this.onKeep,
    required this.onDismiss,
  });

  final String label;
  final int count;
  final VoidCallback onKeep;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final Color foreground = colors.onTertiaryContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.push_pin_outlined, size: 20, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Keep "$label" in your list? You have written it $count times.',
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
            TextButton(
              onPressed: onKeep,
              style: TextButton.styleFrom(foregroundColor: foreground),
              child: const Text('Keep'),
            ),
            IconButton(
              tooltip: 'Not now',
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 20, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.selected,
    required this.labelFor,
    required this.onRemove,
    required this.onDone,
  });

  final List<String> selected;
  final String Function(String path) labelFor;
  final ValueChanged<String> onRemove;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selected.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final String path in selected)
                    InputChip(
                      label: Text(labelFor(path)),
                      onDeleted: () => onRemove(path),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
