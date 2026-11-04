import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/writes/rejected_writes.dart';

// For MaterialApp.builder: a refusal can arrive on any screen, long after the
// one that made the change has closed, so the banner sits above the navigator
// and stays until dismissed.
Widget rejectedWritesBuilder(BuildContext context, Widget? child) =>
    _RejectedWritesFrame(child: child ?? const SizedBox.shrink());

class _RejectedWritesFrame extends ConsumerWidget {
  const _RejectedWritesFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RejectedWrite> rejected = ref.watch(rejectedWritesProvider);

    // The same tree whether or not the banner shows, so showing it does not
    // remount the navigator and lose its routes.
    return Column(
      children: [
        RejectedWritesBanner(rejected: rejected),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: rejected.isNotEmpty,
            child: child,
          ),
        ),
      ],
    );
  }
}

class RejectedWritesBanner extends ConsumerWidget {
  const RejectedWritesBanner({super.key, required this.rejected});

  static const String dismissLabel = 'Dismiss';

  final List<RejectedWrite> rejected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rejected.isEmpty) {
      return const SizedBox.shrink();
    }

    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle text = TextStyle(color: colors.onErrorContainer);

    // Above the navigator there is no Overlay, so nothing here may show a
    // tooltip.
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height / 3,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              children: [
                for (final RejectedWrite item in rejected)
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          Icons.sync_problem,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.what,
                                style: text.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(item.reason, style: text),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(rejectedWritesProvider.notifier)
                              .dismiss(item),
                          child: Text(dismissLabel, style: text),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
