import 'package:flutter/material.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/sync_status.dart';

// A pushed page in the Day Dial style: a back circle and an optional action
// circle over a scrolling body that opens with a Display title.
class DialPage extends StatelessWidget {
  const DialPage({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.action,
    required this.children,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final bool canPop = Navigator.of(context).canPop();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: SizedBox(
                height: DialSize.minTapTarget,
                child: Row(
                  children: <Widget>[
                    if (canPop)
                      CircleButton(
                        icon: DialGlyph.left,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    const Spacer(),
                    ?action,
                  ],
                ),
              ),
            ),
            const OfflineBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  DialSpace.gutter,
                  2,
                  DialSpace.gutter,
                  50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                      child: Semantics(
                        header: true,
                        headingLevel: 1,
                        child: Row(
                          children: <Widget>[
                            if (leading != null) ...<Widget>[
                              leading!,
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                style: DialTypeScale.displayXL.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  height: 1.05,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(
                          subtitle!,
                          style: DialTypeScale.bodyS.copyWith(
                            color: colors.muted,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ...children,
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

// The 24 pt card: surface, a line rim, and the card shadow in light.
class DialCard extends StatelessWidget {
  const DialCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DialRadius.card),
        boxShadow: DialShadows.card(theme.brightness),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

// A hairline between two rows of a card, inset to the text.
class CardDivider extends StatelessWidget {
  const CardDivider({super.key, required this.indent});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Divider(height: 1, thickness: 1, color: DialColors.of(context).line),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = DialTypeScale.label.copyWith(
      fontSize: 13,
      height: 1,
      color: DialColors.of(context).muted,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 10),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: style)),
          if (trailing != null)
            Text(trailing!, style: style.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class PageFootnote extends StatelessWidget {
  const PageFootnote(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
    child: Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: DialTypeScale.bodyS.copyWith(
        fontSize: 12.5,
        height: 1.5,
        color: DialColors.of(context).muted,
      ),
    ),
  );
}
