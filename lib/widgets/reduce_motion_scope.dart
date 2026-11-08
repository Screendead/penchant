import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/providers/reduce_motion_provider.dart';

/// Overrides `MediaQuery.disableAnimations` for everything below it with the
/// device's saved motion choice. It must sit in `MaterialApp.builder`, above the
/// Navigator, so routes, dialogs and sheets read the override too.
class ReduceMotionScope extends ConsumerWidget {
  const ReduceMotionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MediaQueryData data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        disableAnimations: ref
            .watch(reduceMotionProvider)
            .resolve(system: data.disableAnimations),
      ),
      child: child,
    );
  }
}
