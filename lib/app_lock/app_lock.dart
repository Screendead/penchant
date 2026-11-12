import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/app_lock/device_auth.dart';
import 'package:tracker/errors/report_error.dart';

class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.obscured = false,
    this.authenticating = false,
    this.prompted = false,
  });

  final bool enabled;
  final bool locked;

  /// The app is inactive or in the background with the lock on: a plain
  /// cover, so the app switcher's snapshot shows no journal.
  final bool obscured;
  final bool authenticating;

  /// Whether this lock has already asked once by itself; after a cancel the
  /// lock screen waits for its button.
  final bool prompted;

  bool get covered => locked || obscured;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    bool? obscured,
    bool? authenticating,
    bool? prompted,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    obscured: obscured ?? this.obscured,
    authenticating: authenticating ?? this.authenticating,
    prompted: prompted ?? this.prompted,
  );
}

enum LockToggleResult { done, unavailable, notConfirmed }

/// The saved choice, read before the first frame (`startApp`), so a locked
/// journal never shows while it loads.
final appLockSavedProvider = Provider<bool>((Ref ref) => false);

/// A failed read leaves the lock off rather than shut the user out.
Future<bool> readAppLockChoice() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppLock.key) ?? false;
  } catch (e, stack) {
    reportError(e, stack, context: 'while reading the app lock choice');
    return false;
  }
}

final appLockClockProvider = Provider<DateTime Function()>(
  (Ref ref) => DateTime.now,
);

/// Settings › App lock, kept on this device only: on launch, and on return
/// after [grace] away, the journal stays behind Face ID, Touch ID or the
/// device passcode.
final appLockProvider = NotifierProvider<AppLock, AppLockState>(AppLock.new);

class AppLock extends Notifier<AppLockState> {
  static const String key = 'appLock';
  static const Duration grace = Duration(minutes: 1);
  static const String reason = 'Unlock your journal';

  DateTime? _leftAt;

  @override
  AppLockState build() {
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onStateChange: _onLifecycle,
    );
    ref.onDispose(lifecycle.dispose);
    final bool saved = ref.read(appLockSavedProvider);
    return AppLockState(enabled: saved, locked: saved);
  }

  void _onLifecycle(AppLifecycleState lifecycle) {
    if (!state.enabled) return;
    switch (lifecycle) {
      // The Mac turns inactive whenever another app has focus, and has no
      // switcher snapshot to hide from.
      case AppLifecycleState.inactive:
        if (defaultTargetPlatform != TargetPlatform.macOS) {
          state = state.copyWith(obscured: true);
        }
      // The system's own authentication sheet only makes the app inactive,
      // so the clock starts on leaving for real.
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _leftAt ??= ref.read(appLockClockProvider)();
        state = state.copyWith(obscured: true);
      case AppLifecycleState.resumed:
        final DateTime? left = _leftAt;
        _leftAt = null;
        final bool expired =
            left != null &&
            !state.authenticating &&
            ref.read(appLockClockProvider)().difference(left) >= grace;
        state = state.copyWith(
          obscured: false,
          locked: state.locked || expired,
          prompted: expired ? false : state.prompted,
        );
    }
  }

  /// The lock screen's first look: asks once by itself.
  Future<void> promptOnce() async {
    if (state.prompted || !state.locked) return;
    state = state.copyWith(prompted: true);
    await unlock();
  }

  Future<void> unlock() async {
    if (state.authenticating || !state.locked) return;
    state = state.copyWith(authenticating: true, prompted: true);
    AuthOutcome outcome;
    try {
      outcome = await ref.read(deviceAuthProvider).authenticate(reason);
    } catch (e, stack) {
      reportError(e, stack, context: 'while unlocking the app');
      outcome = AuthOutcome.failed;
    }
    switch (outcome) {
      case AuthOutcome.success:
        state = state.copyWith(authenticating: false, locked: false);
      // With no passcode left on the device nothing could ever open the
      // lock, and whoever removed it holds the unlocked device.
      case AuthOutcome.unavailable:
        await _save(false);
        state = state.copyWith(
          enabled: false,
          authenticating: false,
          locked: false,
        );
      case AuthOutcome.cancelled:
      case AuthOutcome.failed:
        state = state.copyWith(authenticating: false);
    }
  }

  /// Turning the lock on first proves the device can open it.
  Future<LockToggleResult> setEnabled(bool on) async {
    if (!on) {
      state = state.copyWith(enabled: false, locked: false, obscured: false);
      await _save(false);
      return LockToggleResult.done;
    }
    final DeviceAuth auth = ref.read(deviceAuthProvider);
    try {
      if (!(await auth.status()).available) {
        return LockToggleResult.unavailable;
      }
      state = state.copyWith(authenticating: true);
      final AuthOutcome outcome = await auth.authenticate('Turn on App lock');
      if (outcome == AuthOutcome.unavailable) {
        return LockToggleResult.unavailable;
      }
      if (outcome != AuthOutcome.success) {
        return LockToggleResult.notConfirmed;
      }
    } catch (e, stack) {
      reportError(e, stack, context: 'while turning on app lock');
      return LockToggleResult.notConfirmed;
    } finally {
      state = state.copyWith(authenticating: false);
    }
    state = state.copyWith(enabled: true);
    await _save(true);
    return LockToggleResult.done;
  }

  // A failed save still applies the choice until the app closes.
  Future<void> _save(bool on) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, on);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the app lock choice');
    }
  }
}
