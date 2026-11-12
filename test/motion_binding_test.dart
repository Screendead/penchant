import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/motion_binding.dart';
import 'package:tracker/providers/reduce_motion_provider.dart';
import 'package:tracker/widgets/reduce_motion_scope.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding with MotionOverride {}

final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

Widget _app(MotionPreference motion) => ProviderScope(
  overrides: [reduceMotionProvider.overrideWith(() => _Fixed(motion))],
  child: MaterialApp(
    navigatorKey: _navigator,
    builder: (BuildContext context, Widget? child) =>
        ReduceMotionScope(child: child!),
    home: const SizedBox.shrink(),
  ),
);

class _Fixed extends ReduceMotion {
  _Fixed(this.motion);

  final MotionPreference motion;

  @override
  MotionPreference build() => motion;
}

/// Opens a modal sheet and reports whether its 250 ms entrance is over after
/// 50 ms: the framework scales a controller's duration to 5% when
/// `SemanticsBinding.disableAnimations` is true.
Future<bool> _sheetUpAfter50ms(WidgetTester tester) async {
  late final Animation<double> animation;
  showModalBottomSheet<void>(
    context: _navigator.currentContext!,
    builder: (BuildContext context) {
      animation = ModalRoute.of(context)!.animation!;
      return const SizedBox(height: 200);
    },
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return animation.isCompleted;
}

void main() {
  _Binding();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  testWidgets('Reduce collapses a modal sheet with the system flag off', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(MotionPreference.reduce));
    expect(await _sheetUpAfter50ms(tester), isTrue);
  });

  testWidgets('Full animates a modal sheet with the system flag on', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_app(MotionPreference.full));
    expect(await _sheetUpAfter50ms(tester), isFalse);
  });

  testWidgets('Follow system collapses it with the system flag on', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_app(MotionPreference.system));
    expect(await _sheetUpAfter50ms(tester), isTrue);
  });
}
