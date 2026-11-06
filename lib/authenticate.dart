import 'package:flutter/material.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/register.dart';
import 'package:tracker/sign_in.dart';
import 'package:tracker/widgets/penchant_mark.dart';
import 'package:tracker/widgets/settings_card.dart';

// One screen for signing in and creating an account: the icon and wordmark,
// a segmented control between the two forms, and the privacy line.
class Authenticate extends StatefulWidget {
  const Authenticate({super.key});

  static const Key signInTab = Key('auth-sign-in');
  static const Key registerTab = Key('auth-register');

  @override
  State<Authenticate> createState() => _AuthenticateState();
}

class _AuthenticateState extends State<Authenticate> {
  bool _register = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = DialColors.of(context).muted;
    final Duration fade = MediaQuery.disableAnimationsOf(context)
        ? DialMotion.reducedFade
        : const Duration(milliseconds: 260);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewport) =>
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(26, 73, 26, 6),
                        child: Column(
                          // The privacy line sits at the foot of a tall
                          // screen and after the form on a short one.
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Column(
                              children: <Widget>[
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: DialShadows.pop(
                                      theme.brightness,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: const PenchantMark(size: 92),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Penchant',
                                    style: DialTypeScale.displayXL.copyWith(
                                      fontSize: 42,
                                      height: 1,
                                      letterSpacing: -0.8,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: DialSpace.xs),
                                Text(
                                  'A private journal of your days.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: DialFonts.text,
                                    fontSize: 15.5,
                                    height: 1.4,
                                    color: muted,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _AuthSegments(
                                  register: _register,
                                  onChanged: (bool register) =>
                                      setState(() => _register = register),
                                ),
                                const SizedBox(height: 18),
                                AnimatedSwitcher(
                                  duration: fade,
                                  child: _register
                                      ? const Register(
                                          key: ValueKey<bool>(true),
                                        )
                                      : const SignIn(
                                          key: ValueKey<bool>(false),
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: DialSpace.xl),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                StrokeIcon(
                                  DialGlyph.shield,
                                  size: 14,
                                  color: muted,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Your journal is private to your account.',
                                    textAlign: TextAlign.center,
                                    style: CardStyles.foot(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

// Sign in or Create account: a recessed track whose surface thumb slides to
// the chosen side.
class _AuthSegments extends StatelessWidget {
  const _AuthSegments({required this.register, required this.onChanged});

  final bool register;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final Duration slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return Container(
      padding: const EdgeInsets.all(DialSpace.xxs),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(DialRadius.pill),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AnimatedAlign(
              duration: slide,
              curve: Curves.easeOutCubic,
              alignment: register
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(DialRadius.pill),
                    // The thumb alone marks the choice, so its ring is
                    // outline (3:1 on the track), not the mock-up's shadow.
                    border: Border.all(color: theme.colorScheme.outline),
                    boxShadow: DialShadows.tiny(theme.brightness),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _Segment(
                  key: Authenticate.signInTab,
                  label: 'Sign in',
                  selected: !register,
                  onTap: () => onChanged(false),
                ),
              ),
              Expanded(
                child: _Segment(
                  key: Authenticate.registerTab,
                  label: 'Create account',
                  selected: register,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool ring =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Semantics(
      button: true,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (bool focused) => setState(() => _focused = focused),
        customBorder: const StadiumBorder(),
        child: Container(
          constraints: const BoxConstraints(minHeight: DialSize.minTapTarget),
          alignment: Alignment.center,
          decoration: ring
              ? ShapeDecoration(
                  shape: StadiumBorder(
                    side: BorderSide(color: scheme.primary, width: 2),
                  ),
                )
              : null,
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: DialFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1,
              color: widget.selected
                  ? scheme.onSurface
                  : DialColors.of(context).muted,
            ),
          ),
        ),
      ),
    );
  }
}
