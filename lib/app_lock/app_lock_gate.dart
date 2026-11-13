import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/app_lock/app_lock.dart';
import 'package:tracker/app_lock/device_auth.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/penchant_mark.dart';

/// Keeps the app mounted under the lock, so its pages and state survive, but
/// out of reach: no semantics, focus, pointer or tickers reach it while
/// covered. It sits in `MaterialApp.builder` above everything that can name a
/// habit or a write.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLockState lock = ref.watch(appLockProvider);
    final bool covered = lock.covered;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ExcludeSemantics(
          excluding: covered,
          child: ExcludeFocus(
            excluding: covered,
            child: AbsorbPointer(
              absorbing: covered,
              child: TickerMode(enabled: !covered, child: child),
            ),
          ),
        ),
        if (lock.locked) const LockScreen() else if (covered) const _Cover(),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: const Center(child: PenchantMark(size: 64)),
  );
}

/// What a locked app shows: the mark, a line and one way in. It names
/// nothing from the journal.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  static const String title = 'Penchant is locked';

  static String unlockLabel(Biometry biometry) =>
      'Unlock with ${unlockMethod(biometry)}';

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  Biometry _biometry = Biometry.none;

  @override
  void initState() {
    super.initState();
    _readBiometry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).promptOnce();
    });
  }

  Future<void> _readBiometry() async {
    try {
      final DeviceAuthStatus status = await ref
          .read(deviceAuthProvider)
          .status();
      if (mounted) setState(() => _biometry = status.biometry);
    } catch (_) {
      // The button still works; it only names the passcode.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool busy = ref.watch(
      appLockProvider.select((AppLockState s) => s.authenticating),
    );
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DialSpace.gutter),
          child: Column(
            children: <Widget>[
              const Spacer(flex: 3),
              const PenchantMark(size: 64),
              const SizedBox(height: DialSpace.xl),
              Semantics(
                header: true,
                child: Text(
                  LockScreen.title,
                  textAlign: TextAlign.center,
                  style: DialTypeScale.displayL.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => ref.read(appLockProvider.notifier).unlock(),
                  child: Text(LockScreen.unlockLabel(_biometry)),
                ),
              ),
              const SizedBox(height: DialSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
