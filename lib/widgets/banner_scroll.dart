import 'package:flutter/material.dart';

// A banner sits in a column above a screen's content, which takes what is
// left. Unbounded, large text grows it past the screen and leaves the content
// no room, so past a third of the screen it scrolls. The third includes the
// margin, and the scroll view sits inside whatever [frame] draws around it.
class BannerScroll extends StatelessWidget {
  const BannerScroll({
    super.key,
    this.margin = EdgeInsets.zero,
    this.frame = _bare,
    required this.padding,
    required this.child,
  });

  final EdgeInsetsGeometry margin;
  final Widget Function(Widget scroll) frame;
  final EdgeInsetsGeometry padding;
  final Widget child;

  static Widget _bare(Widget scroll) => scroll;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height / 3,
    ),
    child: Padding(
      padding: margin,
      child: frame(SingleChildScrollView(padding: padding, child: child)),
    ),
  );
}
