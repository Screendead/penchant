import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/widgets/banner_scroll.dart';
import 'package:tracker/widgets/pill_drop.dart';
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

    // The same tree whether or not the banner shows. WidgetsApp keys the
    // navigator, so a different tree would move it, but the FocusScope it
    // wraps the navigator in has no key and would be rebuilt.
    // The background fills the status bar and the pill's margins once the
    // banner has pushed the screen below them.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: CustomMultiChildLayout(
        delegate: _BannerOverChild(MediaQuery.paddingOf(context).top),
        children: <Widget>[
          LayoutId(id: _Slot.child, child: child),
          LayoutId(
            id: _Slot.banner,
            child: RejectedWritesBanner(rejected: rejected),
          ),
        ],
      ),
    );
  }
}

enum _Slot { child, banner }

// The banner sits over the screen's own status-bar inset, which the screen
// paints, and pushes the screen down only by as much as it is taller than
// that inset. So the screen follows the banner's height frame by frame
// rather than losing its inset at once.
class _BannerOverChild extends MultiChildLayoutDelegate {
  _BannerOverChild(this.inset);

  final double inset;

  @override
  void performLayout(Size size) {
    final double banner = layoutChild(
      _Slot.banner,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    ).height;
    final double push = (banner - inset).clamp(0, size.height);
    layoutChild(
      _Slot.child,
      BoxConstraints.tightFor(width: size.width, height: size.height - push),
    );
    positionChild(_Slot.child, Offset(0, push));
    positionChild(_Slot.banner, Offset.zero);
  }

  @override
  bool shouldRelayout(_BannerOverChild old) => inset != old.inset;
}

class RejectedWritesBanner extends ConsumerWidget {
  const RejectedWritesBanner({super.key, required this.rejected});

  static const String dismissLabel = 'Dismiss';

  final List<RejectedWrite> rejected;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PillDrop(shown: rejected.isNotEmpty, child: _pill(context, ref));

  Widget _pill(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle text = TextStyle(color: colors.onErrorContainer);

    // Above the navigator there is no Overlay, so nothing here may show a
    // tooltip.
    return SafeArea(
      bottom: false,
      child: BannerScroll(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        frame: (Widget scroll) => Material(
          color: colors.errorContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PillDrop.radius),
            side: BorderSide(color: colors.error.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: scroll,
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          children: [
            for (final RejectedWrite item in rejected)
              Semantics(
                liveRegion: true,
                child: _item(context, ref, item, text),
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    WidgetRef ref,
    RejectedWrite item,
    TextStyle text,
  ) {
    final Widget dismiss = TextButton(
      onPressed: () => ref.read(rejectedWritesProvider.notifier).dismiss(item),
      child: Text(dismissLabel, style: text),
    );
    // Inside the pill's margins, at large text a button beside the message
    // leaves the message no width, so it goes under it.
    final bool stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return Row(
      children: [
        Icon(Icons.sync_problem, color: text.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.what,
                style: text.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(item.reason, style: text),
              if (stacked)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: dismiss,
                ),
            ],
          ),
        ),
        if (!stacked) dismiss,
      ],
    );
  }
}
