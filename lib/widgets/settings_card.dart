import 'package:flutter/material.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// A pushed page in the card style: a back circle over the ground, then the
// page's title as a large heading and its body.
class CardPage extends StatelessWidget {
  const CardPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final NavigatorState? navigator = Navigator.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        leadingWidth: 56,
        automaticallyImplyLeading: false,
        leading: navigator != null && navigator.canPop()
            ? const Padding(
                padding: EdgeInsets.only(left: DialSpace.m),
                child: Center(child: CircleBackButton()),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          DialSpace.gutter,
          2,
          DialSpace.gutter,
          50,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DialSpace.xxs),
            child: Semantics(
              header: true,
              child: Text(title, style: CardStyles.heading(context)),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

// Material's BackButton (so routes and tests find it as one) drawn as the
// design's 40 pt back circle.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: DialShadows.card(theme.brightness),
      ),
      child: BackButton(
        style:
            IconButton.styleFrom(
              fixedSize: const Size.square(DialSize.circleButton),
              minimumSize: const Size.square(DialSize.circleButton),
              iconSize: 20,
              backgroundColor: scheme.surfaceContainerLow,
              foregroundColor: scheme.onSurface,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (Set<WidgetState> s) => s.contains(WidgetState.focused)
                    ? BorderSide(color: scheme.primary, width: 2)
                    : BorderSide(color: colors.line),
              ),
            ),
      ),
    );
  }
}

class CardStyles {
  static TextStyle heading(BuildContext context) =>
      DialTypeScale.displayXL.copyWith(
        fontSize: 34,
        height: 1.05,
        letterSpacing: -0.5,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle foot(BuildContext context) => TextStyle(
    fontFamily: DialFonts.text,
    fontSize: 12.5,
    height: 1.5,
    color: DialColors.of(context).muted,
  );
}

// A small muted heading above a card, the mock-up's "sect".
class CardSectionLabel extends StatelessWidget {
  const CardSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, DialSpace.xl, 6, 10),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: DialFonts.text,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1,
          color: DialColors.of(context).muted,
        ),
      ),
    ),
  );
}

class CardFoot extends StatelessWidget {
  const CardFoot(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
    child: Text(text, style: CardStyles.foot(context)),
  );
}

// Surface, radius 24, a hairline rim and the card shadow in light; rows are
// divided by hairlines inset from the left.
class DialCard extends StatelessWidget {
  const DialCard({
    super.key,
    required this.children,
    this.top = DialSpace.l,
    this.inset = 18,
  });

  final List<Widget> children;
  final double top;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final BorderRadius radius = BorderRadius.circular(DialRadius.card);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: radius,
          border: Border.all(color: colors.line),
          boxShadow: DialShadows.card(theme.brightness),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: inset),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One row of a card: a label, a muted value and an optional trailing glyph or
// widget. Focused from the keyboard it takes the system's 2 pt accent ring,
// inset so the card's clip keeps it whole; Material's focus overlay alone is
// about 1.2:1 against the card.
class CardRow extends StatefulWidget {
  const CardRow({
    super.key,
    required this.label,
    this.subtitle,
    this.value,
    this.glyph,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final Widget? value;
  final DialGlyph? glyph;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool enabled;

  @override
  State<CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<CardRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool enabled = widget.enabled && widget.onTap != null;
    final Color labelColor = widget.danger ? scheme.error : scheme.onSurface;
    final bool ring =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    final TextStyle valueStyle = TextStyle(
      fontFamily: DialFonts.text,
      fontSize: 14,
      height: 1.2,
      color: colors.muted,
    );
    final Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: DialFonts.text,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      height: 1.25,
                      color: labelColor,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        widget.subtitle!,
                        style: valueStyle.copyWith(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.value != null)
              Padding(
                padding: const EdgeInsets.only(left: DialSpace.s),
                child: DefaultTextStyle.merge(
                  style: valueStyle,
                  child: widget.value!,
                ),
              ),
            if (widget.glyph != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: StrokeIcon(widget.glyph!, size: 18, color: colors.muted),
              ),
            if (widget.trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: DialSpace.xs),
                child: widget.trailing!,
              ),
          ],
        ),
      ),
    );

    return Semantics(
      button: widget.onTap != null,
      enabled: widget.onTap == null ? null : enabled,
      child: InkWell(
        onTap: enabled ? widget.onTap : null,
        onFocusChange: (bool focused) => setState(() => _focused = focused),
        child: Stack(
          children: <Widget>[
            Opacity(opacity: widget.enabled ? 1 : 0.5, child: row),
            if (ring)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(DialRadius.tile),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
