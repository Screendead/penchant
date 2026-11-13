import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// The two optional rows an entry can carry beside its triggers: how strong
// the urge was, and a one-line note. The amount sheet, the entry editor and
// the "What was going on?" picker each show both.

const String urgeLabel = 'How strong was the urge?';
const String urgeLowLabel = 'Barely';
const String urgeHighLabel = 'Couldn’t not';
const String noteLabel = 'Note';
const String noteHint = 'Anything to remember';

class _OptionalLabel extends StatelessWidget {
  const _OptionalLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = DialColors.of(context).muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: DialSpace.xs),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: text),
            const TextSpan(text: '  '),
            TextSpan(
              text: 'OPTIONAL',
              semanticsLabel: ', optional',
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontSize: 10,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        style: theme.textTheme.titleSmall?.copyWith(color: muted),
      ),
    );
  }
}

/// Urge from [minUrge] to [maxUrge]; tapping the chosen value clears it.
class UrgeField extends StatelessWidget {
  const UrgeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  static Key keyFor(int urge) => ValueKey<String>('urge-$urge');

  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle ends = DialTypeScale.bodyS.copyWith(
      color: colors.muted,
      fontSize: 12,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _OptionalLabel(urgeLabel),
        Row(
          children: <Widget>[
            for (int urge = minUrge; urge <= maxUrge; urge++) ...<Widget>[
              if (urge > minUrge) const SizedBox(width: 6),
              Expanded(
                child: _UrgeBox(
                  key: keyFor(urge),
                  urge: urge,
                  selected: value == urge,
                  enabled: enabled,
                  onTap: () => onChanged(value == urge ? null : urge),
                  scheme: scheme,
                  line: colors.line,
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: DialSpace.xxs),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(urgeLowLabel, style: ends),
                Text(urgeHighLabel, style: ends),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UrgeBox extends StatelessWidget {
  const _UrgeBox({
    super.key,
    required this.urge,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.scheme,
    required this.line,
  });

  final int urge;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final Color line;

  String get _semanticLabel => switch (urge) {
    minUrge => 'Urge $urge of $maxUrge, $urgeLowLabel',
    maxUrge => 'Urge $urge of $maxUrge, $urgeHighLabel',
    _ => 'Urge $urge of $maxUrge',
  };

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(12);
    return Semantics(
      label: _semanticLabel,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? scheme.primary : line,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                '$urge',
                style: DialTypeScale.monoM.copyWith(
                  fontSize: 16,
                  height: 1,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line note of up to [maxNoteLength] UTF-16 code units.
class NoteField extends StatelessWidget {
  const NoteField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  static const Key fieldKey = ValueKey<String>('entry-note');

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _OptionalLabel(noteLabel),
        TextFormField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          // A pasted line break would make two lines; the rest is the
          // validator's, which counts UTF-16 code units as the cap does.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp('[\r\n]')),
          ],
          style: DialTypeScale.body.copyWith(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: noteHint,
            semanticCounterText: '',
            filled: true,
            fillColor: colors.surface2,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
          validator: (String? value) => noteError(storedNote(value ?? '')),
        ),
      ],
    );
  }
}

/// The note as stored: trimmed, and absent when empty.
String? storedNote(String text) {
  final String trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}
