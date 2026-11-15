import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/calendar_suggestion.dart';
import 'package:tracker/providers/mac_calendar_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/tally_row.dart';

// The accent ring the theme gives focused buttons, for chips and tiles, which
// the chip theme leaves without one.
WidgetStateBorderSide _focusSide(BuildContext context) {
  final Color accent = Theme.of(context).colorScheme.primary;
  return WidgetStateBorderSide.resolveWith(
    (Set<WidgetState> s) => s.contains(WidgetState.focused)
        ? BorderSide(color: accent, width: 2, strokeAlign: 3)
        : BorderSide.none,
  );
}

const String undoLogLabel = 'Undo log';

/// Opens the picker for an entry of [viceID] and returns the chosen
/// triggers, or null when it is dismissed without Done. With [onUndoLog] the
/// sheet also offers Undo log, which closes it with null and calls that.
/// With [at], the entry's time, it offers what the calendar suggests.
Future<List<String>?> showTriggerPicker(
  BuildContext context, {
  required String viceID,
  required String viceName,
  required List<String> initial,
  DateTime? at,
  VoidCallback? onUndoLog,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => TriggerSources(
    viceID: viceID,
    at: at,
    builder: (BuildContext context, TriggerOffers offers) => TriggerPickerSheet(
      viceName: viceName,
      usual: offers.usual,
      promoted: offers.promoted,
      suggested: offers.suggested,
      initial: initial,
      onDone: (List<String> picked) => Navigator.of(context).pop(picked),
      onUndoLog: onUndoLog == null
          ? null
          : () {
              Navigator.of(context).pop();
              onUndoLog();
            },
    ),
  ),
);

/// The chips offered beside the tree: the habit's usual triggers, promoted
/// free text and the calendar's suggestions.
typedef TriggerOffers = ({
  List<String> usual,
  List<String> promoted,
  List<String> suggested,
});

/// Supplies [TriggerOffers] for an entry of [viceID] at [at], so the sheets
/// themselves need neither Firestore, the device store nor the calendar.
class TriggerSources extends ConsumerStatefulWidget {
  const TriggerSources({
    super.key,
    required this.viceID,
    required this.builder,
    this.at,
  });

  final String viceID;
  final DateTime? at;
  final Widget Function(BuildContext context, TriggerOffers offers) builder;

  @override
  ConsumerState<TriggerSources> createState() => _TriggerSourcesState();
}

class _TriggerSourcesState extends ConsumerState<TriggerSources> {
  List<String> promoted = const <String>[];
  List<String> suggested = const <String>[];

  @override
  void initState() {
    super.initState();
    final String? uid = ref.read(userProvider).value?.uid;
    if (uid != null) {
      ref.read(freeTextTriggersProvider).promoted(uid).then((List<String> p) {
        if (mounted) setState(() => promoted = p);
      }, onError: (Object _) {});
    }
    if (widget.at case final DateTime at) {
      readCalendarSuggestions(ref.read(pickerCalendarSourceProvider), at).then((
        List<String> s,
      ) {
        if (mounted && s.isNotEmpty) setState(() => suggested = s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ViceActivity> recent =
        ref
            .watch(
              viceActivityHistoryProvider((
                viceID: widget.viceID,
                limit: ViceActivityHistoryPage.pageSize,
              )),
            )
            .value ??
        const <ViceActivity>[];

    return widget.builder(context, (
      usual: usualTriggers(recent),
      promoted: promoted,
      suggested: suggested,
    ));
  }
}

/// Optional triggers for one entry, in a sheet: [TriggerChoices] over the
/// picked ones and Done. Nothing starts picked but [initial].
class TriggerPickerSheet extends StatefulWidget {
  const TriggerPickerSheet({
    super.key,
    required this.viceName,
    required this.onDone,
    this.usual = const <String>[],
    this.promoted = const <String>[],
    this.suggested = const <String>[],
    this.initial = const <String>[],
    this.roots = triggerTree,
    this.onUndoLog,
  });

  final String viceName;
  final List<String> usual;
  final List<String> promoted;
  final List<String> suggested;
  final List<String> initial;
  final List<TriggerNode> roots;
  final ValueChanged<List<String>> onDone;
  final VoidCallback? onUndoLog;

  static const String calendarLabel = 'Suggested from your calendar';
  static const String calendarHint =
      'A calendar event ended in the hour before';

  @override
  State<TriggerPickerSheet> createState() => _TriggerPickerSheetState();
}

class _TriggerPickerSheetState extends State<TriggerPickerSheet> {
  late List<String> selected = <String>[...widget.initial];

  void changed(List<String> next) => setState(() => selected = next);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double height = MediaQuery.sizeOf(context).height;
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!crampedByKeyboard(context))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DialSpace.xl,
                  DialSpace.xl,
                  DialSpace.xl,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'What was going on?',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: DialSpace.xxs),
                    Text(
                      'Optional. Tap any that fit.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: DialColors.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(DialSpace.m),
                children: <Widget>[
                  TriggerChoices(
                    viceName: widget.viceName,
                    usual: widget.usual,
                    promoted: widget.promoted,
                    suggested: widget.suggested,
                    roots: widget.roots,
                    selected: selected,
                    onChanged: changed,
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: DialColors.of(context).line),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DialSpace.m,
                  vertical: DialSpace.s,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (selected.isNotEmpty) ...<Widget>[
                      SelectedTriggers(selected: selected, onChanged: changed),
                      const SizedBox(height: DialSpace.s),
                    ],
                    Row(
                      children: <Widget>[
                        if (widget.onUndoLog
                            case final VoidCallback undo) ...<Widget>[
                          UndoLogButton(onPressed: undo),
                          const SizedBox(width: DialSpace.s),
                        ],
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            onPressed: () =>
                                widget.onDone(List<String>.of(selected)),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above a landscape phone's keyboard a sheet's title would leave the list no
/// room for the field being typed in.
bool crampedByKeyboard(BuildContext context) {
  final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return keyboard > 0 && MediaQuery.sizeOf(context).height - keyboard < 320;
}

class UndoLogButton extends StatelessWidget {
  const UndoLogButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Undo log, removing this entry',
    excludeSemantics: true,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
      onPressed: onPressed,
      child: const Text(undoLogLabel),
    ),
  );
}

/// The picked triggers as removable chips, saying when no more fit.
class SelectedTriggers extends StatelessWidget {
  const SelectedTriggers({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xxs,
          children: <Widget>[
            for (final String path in selected)
              InputChip(
                label: Text(triggerDisplay(path)),
                side: _focusSide(context),
                deleteButtonTooltipMessage: 'Remove ${triggerDisplay(path)}',
                onDeleted: () =>
                    onChanged(selected.where((String p) => p != path).toList()),
              ),
          ],
        ),
        if (selected.length >= maxTriggers)
          Padding(
            padding: const EdgeInsets.only(top: DialSpace.xxs),
            child: Text(
              'Up to $maxTriggers per entry',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DialColors.of(context).muted,
              ),
            ),
          ),
      ],
    );
  }
}

/// One field searching the starter tree across areas, which adds what it
/// does not name as free text (a choice once used [freeTextPromotionUses]
/// times); while it is empty, the calendar's suggestions and the habit's
/// usual triggers as one-tap chips and the tree two levels deep. [selected] is the parent's;
/// each change comes back through [onChanged].
class TriggerChoices extends StatefulWidget {
  const TriggerChoices({
    super.key,
    required this.viceName,
    required this.selected,
    required this.onChanged,
    this.usual = const <String>[],
    this.promoted = const <String>[],
    this.suggested = const <String>[],
    this.roots = triggerTree,
  });

  static const String searchHint = 'Search tags, or add your own';

  final String viceName;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final List<String> usual;
  final List<String> promoted;
  final List<String> suggested;
  final List<TriggerNode> roots;

  @override
  State<TriggerChoices> createState() => _TriggerChoicesState();
}

class _TriggerChoicesState extends State<TriggerChoices> {
  String? root;
  final TextEditingController freeText = TextEditingController();
  final FocusNode freeTextFocus = FocusNode();
  String? freeTextError;

  List<String> get selected => widget.selected;

  bool get full => selected.length >= maxTriggers;

  String get query => freeText.text.trim();

  @override
  void initState() {
    super.initState();
    freeText.addListener(_typed);
  }

  String _lastText = '';

  void _typed() {
    if (freeText.text == _lastText) return;
    _lastText = freeText.text;
    setState(() => freeTextError = null);
  }

  bool _under(String path, String id) =>
      path == id || path.startsWith('$id$triggerPathSeparator');

  int pickedUnder(String id) =>
      selected.where((String p) => _under(p, id)).length;

  void _edit(void Function(List<String> next) edit) {
    final List<String> next = <String>[...selected];
    edit(next);
    widget.onChanged(next);
  }

  void toggle(String path) => _edit((List<String> next) {
    if (!next.remove(path) && !full) next.add(path);
  });

  // Opening an area records it; a child picked inside replaces it.
  void openRoot(String id) {
    setState(() => root = id);
    if (pickedUnder(id) == 0 && !full) _edit((List<String> n) => n.add(id));
  }

  void toggleChild(String parent, String path) => _edit((List<String> next) {
    if (!next.remove(path) && (!full || next.contains(parent))) {
      next
        ..remove(parent)
        ..add(path);
    }
  });

  void pick(String path) {
    final List<String> ids = path.split(triggerPathSeparator);
    if (ids.length == 1) return toggle(path);
    toggleChild(ids.first, path);
  }

  List<String> exactMatches(List<String> found) => <String>[
    for (final String path in found)
      if (triggerLabelIs(triggerShortDisplay(path), query)) path,
  ];

  // A label naming one tag picks it; one naming several (Hard conversation
  // is under two areas) leaves the choice to a tap.
  void submit() {
    final List<String> exact = exactMatches(
      searchTriggers(query, roots: widget.roots),
    );
    if (exact.isEmpty) return addFreeText();
    if (exact.length > 1) return;
    if (!selected.contains(exact.single)) pick(exact.single);
    freeText.clear();
  }

  // The field's maxLength counts characters, the rules UTF-16 code units, so
  // an emoji-heavy label can fit the field and still be too long to store.
  void addFreeText() {
    final String label = query;
    if (label.isEmpty) return;
    final String? error = triggersError(<String>[label]);
    setState(() => freeTextError = error);
    if (error != null) return;
    if (!selected.contains(label) && !full) {
      _edit((List<String> n) => n.add(label));
    }
    freeText.clear();
  }

  @override
  void dispose() {
    freeText.dispose();
    freeTextFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TriggerNode? open = root == null
        ? null
        : widget.roots.where((TriggerNode n) => n.id == root).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
          child: _FreeTextField(
            controller: freeText,
            focusNode: freeTextFocus,
            hint: TriggerChoices.searchHint,
            onSubmit: submit,
            error: freeTextError,
          ),
        ),
        const SizedBox(height: DialSpace.m),
        if (query.isNotEmpty)
          ..._results()
        else if (open == null)
          ..._levelOne(context)
        else
          ..._levelTwo(open),
      ],
    );
  }

  Widget _chip(String label, String value) => FilterChip(
    label: Text(label),
    selected: selected.contains(value),
    side: _focusSide(context),
    onSelected: (_) => toggle(value),
  );

  List<Widget> _results() {
    final List<String> found = searchTriggers(query, roots: widget.roots);
    final bool exact = exactMatches(found).isNotEmpty;
    final int n = found.length;

    return <Widget>[
      Semantics(
        liveRegion: true,
        child: _SectionLabel(
          n == 0 ? 'No tag matches' : '$n matching ${n == 1 ? 'tag' : 'tags'}',
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
        child: Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (final String path in found)
              FilterChip(
                label: Text(
                  triggerLabels(path, roots: widget.roots)!.join(' · '),
                ),
                selected: selected.contains(path),
                side: _focusSide(context),
                onSelected: (_) => pick(path),
              ),
            if (!exact)
              ActionChip(
                avatar: const Icon(Icons.edit_outlined, size: 18),
                label: Text('Add "$query" in your own words'),
                side: _focusSide(context),
                onPressed: addFreeText,
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _levelOne(BuildContext context) {
    final List<String> suggested = widget.suggested;
    final List<String> usual = widget.usual
        .where((String p) => !suggested.contains(p))
        .toList();
    final List<String> promoted = widget.promoted
        .where((String p) => !usual.contains(p))
        .toList();

    return <Widget>[
      if (suggested.isNotEmpty) ...<Widget>[
        const _SectionLabel(TriggerPickerSheet.calendarLabel),
        Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (final String path in suggested)
              FilterChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                showCheckmark: false,
                tooltip: TriggerPickerSheet.calendarHint,
                label: Text(triggerDisplay(path)),
                selected: selected.contains(path),
                side: _focusSide(context),
                onSelected: (_) => toggle(path),
              ),
          ],
        ),
        const SizedBox(height: DialSpace.m),
      ],
      if (usual.isNotEmpty) ...<Widget>[
        _SectionLabel('Usual for ${widget.viceName}'),
        Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (final String path in usual) _chip(triggerDisplay(path), path),
          ],
        ),
        const SizedBox(height: DialSpace.m),
      ],
      if (promoted.isNotEmpty) ...<Widget>[
        const _SectionLabel('Your own'),
        Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (final String label in promoted) _chip(label, label),
          ],
        ),
        const SizedBox(height: DialSpace.m),
      ],
      _SectionLabel(
        usual.isEmpty && promoted.isEmpty ? 'Areas of life' : 'Or browse',
      ),
      _AreaTiles(
        tiles: <Widget>[
          for (final TriggerNode node in widget.roots)
            _RootTile(
              icon: node.icon ?? Icons.label_outline,
              label: node.label,
              picked: pickedUnder(node.id),
              onTap: () => openRoot(node.id),
            ),
        ],
      ),
    ];
  }

  List<Widget> _levelTwo(TriggerNode node) {
    final ThemeData theme = Theme.of(context);

    return <Widget>[
      Row(
        children: <Widget>[
          IconButton(
            tooltip: 'All areas',
            onPressed: () => setState(() => root = null),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: DialSpace.xxs),
          Icon(node.icon, color: theme.colorScheme.onSurface),
          const SizedBox(width: DialSpace.xs),
          Expanded(child: Text(node.label, style: theme.textTheme.titleLarge)),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          DialSpace.xs,
          DialSpace.xxs,
          DialSpace.xs,
          DialSpace.m,
        ),
        child: Text(
          'Pick one to be more specific, or leave it at "${node.label}".',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DialColors.of(context).muted,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
        child: Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (final TriggerNode child in node.children)
              FilterChip(
                label: Text(child.label),
                selected: selected.contains(
                  '${node.id}$triggerPathSeparator${child.id}',
                ),
                side: _focusSide(context),
                onSelected: (_) => toggleChild(
                  node.id,
                  '${node.id}$triggerPathSeparator${child.id}',
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

// Two across while a tile's half of the width holds a two-line label, else
// one; each row as tall as its taller label.
class _AreaTiles extends StatelessWidget {
  const _AreaTiles({required this.tiles});

  final List<Widget> tiles;

  static const double minTileWidth = 150;

  @override
  Widget build(BuildContext context) {
    final bool large =
        MediaQuery.textScalerOf(context).scale(100) >
        100 * TallyGrid.oneColumnAbove;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final int across =
            !large && box.maxWidth >= 2 * minTileWidth + DialSpace.xs ? 2 : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < tiles.length; i += across)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i + across < tiles.length ? DialSpace.xs : 0,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int j = i; j < i + across; j++) ...<Widget>[
                        if (j > i) const SizedBox(width: DialSpace.xs),
                        Expanded(
                          child: j < tiles.length
                              ? tiles[j]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DialSpace.xs,
        0,
        DialSpace.xs,
        DialSpace.xs,
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: DialColors.of(context).muted),
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
  });

  final IconData icon;
  final String label;
  final int picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool active = picked > 0;
    final Color fill = active
        ? scheme.primary
        : DialColors.of(context).surface2;
    final Color ink = active ? scheme.onPrimary : scheme.onSurface;
    final BorderRadius radius = BorderRadius.circular(DialRadius.tile);

    return Semantics(
      button: true,
      label: active ? '$label, $picked picked' : label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          focusColor: Colors.transparent,
          child: _FocusRing(
            radius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DialSpace.s,
                  vertical: DialSpace.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 22, color: ink),
                    const SizedBox(width: DialSpace.xs),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: ink),
                      ),
                    ),
                    if (active)
                      Text(
                        '$picked',
                        style: DialTypeScale.monoS.copyWith(color: ink),
                      ),
                    Icon(Icons.chevron_right, size: 20, color: ink),
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

// Draws the accent ring outside its child while the enclosing InkWell has
// keyboard focus.
class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool focused = Focus.of(context).hasPrimaryFocus;
    if (!focused) return child;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: child,
    );
  }
}

class _FreeTextField extends StatelessWidget {
  const _FreeTextField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: maxTriggerLength,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: hint,
        errorText: error,
        counterText: '',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: controller.clear,
                  icon: const Icon(Icons.close),
                ),
              IconButton(
                tooltip: 'Add',
                onPressed: onSubmit,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The entry form's triggers: what is picked, and a button that opens the
/// picker.
class TriggersField extends StatelessWidget {
  const TriggersField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.viceID,
    required this.viceName,
    this.at,
    this.enabled = true,
  });

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  // Null until a habit is chosen; the picker needs one for its usual chips.
  final String? viceID;
  final String viceName;
  // The entry's time as the picker opens, for the calendar's suggestion.
  final DateTime Function()? at;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final List<String>? picked = await showTriggerPicker(
      context,
      viceID: viceID!,
      viceName: viceName,
      initial: value,
      at: at?.call(),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (value.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: DialSpace.xs,
            runSpacing: DialSpace.xxs,
            children: <Widget>[
              for (final String trigger in value)
                InputChip(
                  label: Text(triggerDisplay(trigger)),
                  side: _focusSide(context),
                  deleteButtonTooltipMessage:
                      'Remove ${triggerDisplay(trigger)}',
                  onDeleted: enabled
                      ? () => onChanged(
                          value.where((String t) => t != trigger).toList(),
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: DialSpace.xxs),
        ],
        TextButton.icon(
          onPressed: enabled && viceID != null ? () => _open(context) : null,
          icon: const Icon(Icons.add),
          label: Text(
            value.isEmpty ? 'What was going on? (optional)' : 'Change triggers',
          ),
          style: TextButton.styleFrom(textStyle: theme.textTheme.labelLarge),
        ),
      ],
    );
  }
}
