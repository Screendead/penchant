import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/register.dart';
import 'package:tracker/sign_in.dart';
import 'package:tracker/widgets/auth_parts.dart';
import 'package:tracker/widgets/penchant_mark.dart';
import 'package:tracker/widgets/settings_card.dart';

// One screen for signing in and creating an account: the icon and wordmark,
// a segmented control between the two forms, and the privacy line.
class Authenticate extends StatefulWidget {
  const Authenticate({super.key});

  static const Key signInTab = Key('auth-sign-in');
  static const Key registerTab = Key('auth-register');
  static const Key guestStart = Key('auth-guest');

  @override
  State<Authenticate> createState() => _AuthenticateState();
}

class _AuthenticateState extends State<Authenticate> {
  bool _register = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = DialColors.of(context).muted;
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewport) =>
              SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 440,
                      minHeight: viewport.maxHeight,
                    ),
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
                                  boxShadow: DialShadows.pop(theme.brightness),
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
                              _FormSwitcher(
                                register: _register,
                                reduced: reduced,
                              ),
                              const _GuestStart(),
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
    );
  }
}

// The thumb, the form fade and the height change run together on these.
const Duration _switchDuration = Duration(milliseconds: 260);
const Curve _switchCurve = DialMotion.enter;

// A fade-through between the two forms: the old one is gone by a third of the
// way, the new one fades in and settles 6 pt down (the mock-up's travel), and
// the box eases to the new form's height so what sits below glides. Under
// reduced motion the forms cross-fade in place and the height changes at once.
class _FormSwitcher extends StatelessWidget {
  const _FormSwitcher({required this.register, required this.reduced});

  final bool register;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final Key current = ValueKey<bool>(register);
    return AnimatedSize(
      // A zero duration trips RenderAnimatedSize's layout assertion, and
      // dropping the widget under reduced motion would remount the forms.
      duration: reduced ? const Duration(microseconds: 1) : _switchDuration,
      curve: _switchCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduced ? DialMotion.reducedFade : _switchDuration,
        // Outgoing forms are positioned so that only the incoming one sizes
        // the box, and both are top-aligned so their shared fields line up.
        layoutBuilder: (Widget? currentChild, List<Widget> previous) => Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: <Widget>[
            for (final Widget child in previous)
              Positioned(top: 0, left: 0, right: 0, child: child),
            ?currentChild,
          ],
        ),
        transitionBuilder: (Widget child, Animation<double> animation) {
          if (reduced) {
            return FadeTransition(opacity: animation, child: child);
          }
          if (child.key != current) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0.65, 1, curve: Curves.easeIn),
              ),
              child: child,
            );
          }
          final Animation<double> enter = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.35, 1, curve: _switchCurve),
          );
          return FadeTransition(
            opacity: enter,
            child: AnimatedBuilder(
              animation: enter,
              builder: (BuildContext context, Widget? child) =>
                  Transform.translate(
                    offset: Offset(0, -6 * (1 - enter.value)),
                    child: child,
                  ),
              child: child,
            ),
          );
        },
        child: register
            ? const Register(key: ValueKey<bool>(true))
            : const SignIn(key: ValueKey<bool>(false)),
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
        : _switchDuration;
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
              curve: _switchCurve,
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

// Signs in anonymously; main.dart then shows the journal as for any user.
class _GuestStart extends ConsumerStatefulWidget {
  const _GuestStart();

  @override
  ConsumerState<_GuestStart> createState() => _GuestStartState();
}

class _GuestStartState extends ConsumerState<_GuestStart> {
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider).startAsGuest();
    } catch (e, stack) {
      reportError(e, stack, context: 'while starting without an account');
      if (mounted) {
        setState(
          () => _error = AccountCopy.startAsGuestFailed(authErrorMessage(e)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: DialSpace.m),
        OutlinedButton(
          key: Authenticate.guestStart,
          onPressed: _busy ? null : _start,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(DialSize.minTapTarget),
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outline),
            textStyle: const TextStyle(
              fontFamily: DialFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          child: _busy
              ? Semantics(
                  label: AccountCopy.startAsGuest,
                  child: const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Text(AccountCopy.startAsGuest),
        ),
        if (_error != null) AuthErrorPill(_error!),
      ],
    );
  }
}
