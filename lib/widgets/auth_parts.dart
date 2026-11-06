import 'package:flutter/material.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// The pieces of the sign-in screen: pill fields with a leading glyph, the
// error pill, the password checklist and the full-width primary button.

const TextStyle _fieldText = TextStyle(
  fontFamily: DialFonts.text,
  fontWeight: FontWeight.w500,
  fontSize: 15.5,
  height: 1.2,
);

class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.glyph,
    this.obscurable = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final DialGlyph glyph;
  final bool obscurable;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final Color muted = DialColors.of(context).muted;
    return TextFormField(
      controller: widget.controller,
      obscureText: widget.obscurable && _obscured,
      keyboardType: widget.keyboardType,
      autocorrect: false,
      enableSuggestions: !widget.obscurable,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      style: _fieldText.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        hintText: widget.hint,
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 18, right: 10),
          // The decorator stretches its prefix to the field's height.
          child: Center(
            widthFactor: 1,
            child: StrokeIcon(widget.glyph, size: 19, color: muted),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minHeight: 52),
        suffixIcon: widget.obscurable
            ? Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: _obscured ? 'Show password' : 'Hide password',
                  icon: StrokeIcon(
                    _obscured ? DialGlyph.eye : DialGlyph.eyeOff,
                    size: 19,
                    color: muted,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              )
            : null,
      ),
    );
  }
}

// A refused sign-in or registration, announced as it appears.
class AuthErrorPill extends StatelessWidget {
  const AuthErrorPill(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: DialSpace.s),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: <Widget>[
              StrokeIcon(DialGlyph.alert, size: 18, color: scheme.error),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontFamily: DialFonts.text,
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                    height: 1.3,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordRules {
  static const String length = '8+ characters';
  static const String upper = 'An upper-case letter';
  static const String lower = 'A lower-case letter';
  static const String digit = 'A number';
  static const String match = 'Passwords match';

  static Map<String, bool> check(String password, String confirmation) =>
      <String, bool>{
        length: password.length >= 8,
        upper: password.contains(RegExp(r'[A-Z]')),
        lower: password.contains(RegExp(r'[a-z]')),
        digit: password.contains(RegExp(r'[0-9]')),
        match: password.isNotEmpty && password == confirmation,
      };
}

// The password rule as a live checklist, two columns.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({super.key, required this.checks});

  final Map<String, bool> checks;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, bool>> items = checks.entries.toList();
    return Padding(
      padding: const EdgeInsets.only(top: DialSpace.s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: DialColors.of(context).line),
        ),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < items.length; i += 2)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: _Check(items[i].key, ok: items[i].value)),
                    const SizedBox(width: DialSpace.s),
                    Expanded(
                      child: i + 1 < items.length
                          ? _Check(items[i + 1].key, ok: items[i + 1].value)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.label, {required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Semantics(
      checked: ok,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            AnimatedContainer(
              duration: duration,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? colors.clearInk : Colors.transparent,
                // The ring marks an unmet rule, so it is outline, not line.
                border: ok
                    ? null
                    : Border.all(color: scheme.outline, width: 1.5),
              ),
              child: AnimatedScale(
                scale: ok ? 1 : 0,
                duration: duration,
                curve: Curves.easeOutBack,
                child: StrokeIcon(
                  DialGlyph.check,
                  size: 12,
                  color: scheme.surfaceContainerLow,
                ),
              ),
            ),
            const SizedBox(width: DialSpace.xs),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: duration,
                style: TextStyle(
                  fontFamily: DialFonts.text,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  height: 1.2,
                  color: ok ? scheme.onSurface : colors.muted,
                ),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The full-width ink button; while busy it keeps its ink and shows a spinner.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ElevatedButton(
        onPressed: busy ? () {} : onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(
            fontFamily: DialFonts.text,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        child: busy
            ? Semantics(
                label: label,
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.onPrimary,
                    backgroundColor: scheme.onPrimary.withValues(alpha: 0.3),
                  ),
                ),
              )
            : Text(label),
      ),
    );
  }
}
