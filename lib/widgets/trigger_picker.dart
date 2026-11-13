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
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

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

/// The urge and note the picker asks for when it is not opened from the
/// amount sheet, which asks for them itself.
typedef PickerAnswers = ({int? urge, String? note});

/// What the picker closes with: the triggers, and with [showTriggerPicker]'s
/// `answers` the urge and note (else null).
typedef TriggerPick = ({List<String> triggers, PickerAnswers? answers});

/// Opens the picker for an entry of [viceID] and returns the chosen
/// triggers, or null when it is dismissed without Done. With [answers] it
/// also asks for the urge and note, starting from those. With [onUndoLog] the
/// sheet also offers Undo log, which closes it with null and calls that.
/// With [at], the entry's time, it offers what the calendar suggests.
Future<TriggerPick?> showTriggerPicker(
  BuildContext context, {
  required String viceID,
  required String viceName,
  required List<String> initial,
  PickerAnswers? answers,
  DateTime? at,
  VoidCallback? onUndoLog,
}) => showModalBottomSheet<TriggerPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => _TriggerPickerLoader(
    viceID: viceID,
    viceName: viceName,
    initial: initial,
    answers: answers,
    at: at,
    onUndoLog: onUndoLog,
  ),
);

// Supplies the habit's usual triggers, the promoted free text and the
// calendar's suggestion, so the sheet itself needs neither Firestore, the
// device store nor the calendar.
class _TriggerPickerLoader extends ConsumerStatefulWidget {
  const _TriggerPickerLoader({
    required this.viceID,
    required this.viceName,
    required this.initial,
    this.answers,
    this.at,
    this.onUndoLog,
  });

  final String viceID;
  final String viceName;
  final List<String> initial;
  final PickerAnswers? answers;
  final DateTime? at;
  final VoidCallback? onUndoLog;

  @override
  ConsumerState<_TriggerPickerLoader> createState() =>
      _TriggerPickerLoaderState();
}

class _TriggerPickerLoaderState extends ConsumerState<_TriggerPickerLoader> {
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

    return TriggerPickerSheet(
      viceName: widget.viceName,
      usual: usualTriggers(recent),
      promoted: promoted,
      suggested: suggested,
      initial: widget.initial,
      answers: widget.answers,
      onDone: (List<String> picked) =>
          Navigator.of(context).pop((triggers: picked, answers: null)),
      onAnswered: (List<String> picked, PickerAnswers answers) =>
          Navigator.of(context).pop((triggers: picked, answers: answers)),
      onUndoLog: widget.onUndoLog == null
          ? null
          : () {
              Navigator.of(context).pop();
              widget.onUndoLog!();
            },
    );
  }
}

/// Optional triggers for one entry: the calendar's suggestions and the
/// habit's usual ones as one-tap chips, the starter tree two levels deep, and
/// free text, which becomes a choice once used [freeTextPromotionUses] times.
/// Nothing starts picked but [initial].
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
    this.answers,
    this.onAnswered,
    this.onUndoLog,
  });

  final String viceName;
  final List<String> usual;
  final List<String> promoted;
  final List<String> suggested;
  final List<String> initial;
  final List<TriggerNode> roots;
  final ValueChanged<List<String>> onDone;
  // With [answers], the sheet also asks for the urge and note, and Done
  // calls [onAnswered] rather than [onDone].
  final PickerAnswers? answers;
  final void Function(List<String> triggers, PickerAnswers answers)? onAnswered;
  final VoidCallback? onUndoLog;

  static const String calendarLabel = 'Suggested from your calendar';
  static const String calendarHint =
      'A calendar event ended in the hour before';

  @override
  State<TriggerPickerSheet> createState() => _TriggerPickerSheetState();
}

class _TriggerPickerSheetState extends State<TriggerPickerSheet> {
  String? root;
  late final List<String> selected = <String>[...widget.initial];
  final TextEditingController freeText = TextEditingController();
  final FocusNode freeTextFocus = FocusNode();
  bool showFreeText = false;
  String? freeTextError;
  final GlobalKey<FormState> answersForm = GlobalKey<FormState>();
  late int? urge = widget.answers?.urge;
  late final TextEditingController note = TextEditingController(
    text: widget.answers?.note ?? '',
  );
  String? answersError;

  bool get full => selected.length >= maxTriggers;

  bool _under(String path, String id) =>
      path == id || path.startsWith('$id$triggerPathSeparator');

  int pickedUnder(String id) =>
      selected.where((String p) => _under(p, id)).length;

  void toggle(String path) {
    setState(() {
      if (!selected.remove(path) && !full) selected.add(path);
    });
  }

  // Opening an area records it; a child picked inside replaces it.
  void openRoot(String id) {
    setState(() {
      root = id;
      if (pickedUnder(id) == 0 && !full) selected.add(id);
    });
  }

  void toggleChild(String parent, String path) {
    setState(() {
      if (!selected.remove(path) && (!full || selected.contains(parent))) {
        selected
          ..remove(parent)
          ..add(path);
      }
    });
  }

  void openFreeText() {
    setState(() => showFreeText = true);
    freeTextFocus.requestFocus();
  }

  // The field's maxLength counts characters, the rules UTF-16 code units, so
  // an emoji-heavy label can fit the field and still be too long to store.
  void addFreeText() {
    final String label = freeText.text.trim();
    if (label.isEmpty) return;
    final String? error = triggersError(<String>[label]);
    setState(() => freeTextError = error);
    if (error != null) return;
    setState(() {
      if (!selected.contains(label) && !full) selected.add(label);
      freeText.clear();
    });
  }

  void done() {
    final List<String> picked = List<String>.of(selected);
    final void Function(List<String>, PickerAnswers)? onAnswered =
        widget.onAnswered;
    if (widget.answers == null || onAnswered == null) {
      widget.onDone(picked);
      return;
    }
    if (!(answersForm.currentState?.validate() ?? true)) return;
    final String? note = storedNote(this.note.text);
    final String? tooLong = answersTooLong(
      triggers: picked,
      urge: urge,
      note: note,
    );
    setState(() => answersError = tooLong);
    if (tooLong != null) return;
    onAnswered(picked, (urge: urge, note: note));
  }

  @override
  void dispose() {
    freeText.dispose();
    freeTextFocus.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TriggerNode? open = root == null
        ? null
        : widget.roots.where((TriggerNode n) => n.id == root).firstOrNull;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
              padding: const EdgeInsets.fromLTRB(
                DialSpace.m,
                DialSpace.m,
                DialSpace.m,
                DialSpace.m,
              ),
              children: open == null ? _levelOne(context) : _levelTwo(open),
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => FilterChip(
    label: Text(label),
    selected: selected.contains(value),
    side: _focusSide(context),
    onSelected: (_) => toggle(value),
  );

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
      GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: DialSpace.xs,
        crossAxisSpacing: DialSpace.xs,
        childAspectRatio: 3.2,
        children: <Widget>[
          for (final TriggerNode node in widget.roots)
            _RootTile(
              icon: node.icon ?? Icons.label_outline,
              label: node.label,
              picked: pickedUnder(node.id),
              onTap: () => openRoot(node.id),
            ),
          _RootTile(
            icon: Icons.edit_outlined,
            label: 'Your own words',
            picked: 0,
            drills: false,
            onTap: openFreeText,
          ),
        ],
      ),
      if (showFreeText) ...<Widget>[
        const SizedBox(height: DialSpace.m),
        _FreeTextField(
          controller: freeText,
          focusNode: freeTextFocus,
          hint: 'In your own words',
          onSubmit: addFreeText,
          error: freeTextError,
        ),
      ],
      if (widget.answers != null) ...<Widget>[
        const SizedBox(height: DialSpace.m),
        Form(
          key: answersForm,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                UrgeField(
                  value: urge,
                  onChanged: (int? value) => setState(() => urge = value),
                ),
                const SizedBox(height: DialSpace.m),
                NoteField(controller: note),
                if (answersError case final String error) ...<Widget>[
                  const SizedBox(height: DialSpace.xs),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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
          Text(node.label, style: theme.textTheme.titleLarge),
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
      const SizedBox(height: DialSpace.l),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
        child: _FreeTextField(
          controller: freeText,
          focusNode: freeTextFocus,
          hint: 'Something else, in your own words',
          onSubmit: addFreeText,
          error: freeTextError,
        ),
      ),
    ];
  }

  Widget _footer(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: DialColors.of(context).line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DialSpace.m,
          DialSpace.s,
          DialSpace.m,
          DialSpace.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (selected.isNotEmpty) ...<Widget>[
              Wrap(
                spacing: DialSpace.xs,
                runSpacing: DialSpace.xxs,
                children: <Widget>[
                  for (final String path in selected)
                    InputChip(
                      label: Text(triggerDisplay(path)),
                      side: _focusSide(context),
                      deleteButtonTooltipMessage:
                          'Remove ${triggerDisplay(path)}',
                      onDeleted: () => toggle(path),
                    ),
                ],
              ),
              if (full)
                Padding(
                  padding: const EdgeInsets.only(top: DialSpace.xxs),
                  child: Text(
                    'Up to $maxTriggers per entry',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DialColors.of(context).muted,
                    ),
                  ),
                ),
              const SizedBox(height: DialSpace.s),
            ],
            Row(
              children: <Widget>[
                if (widget.onUndoLog case final VoidCallback undo) ...<Widget>[
                  Semantics(
                    button: true,
                    label: 'Undo log, removing this entry',
                    excludeSemantics: true,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: undo,
                      child: const Text(undoLogLabel),
                    ),
                  ),
                  const SizedBox(width: DialSpace.s),
                ],
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    onPressed: done,
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DialSpace.s),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 22, color: ink),
                  const SizedBox(width: DialSpace.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: ink),
                    ),
                  ),
                  if (active)
                    Text(
                      '$picked',
                      style: DialTypeScale.monoS.copyWith(color: ink),
                    ),
                  Icon(
                    drills ? Icons.chevron_right : Icons.add,
                    size: 20,
                    color: ink,
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
    final TriggerPick? picked = await showTriggerPicker(
      context,
      viceID: viceID!,
      viceName: viceName,
      initial: value,
      at: at?.call(),
    );
    if (picked != null) onChanged(picked.triggers);
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
