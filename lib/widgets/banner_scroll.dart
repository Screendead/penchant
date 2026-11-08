import 'package:flutter/material.dart';

// A banner sits in a column above a screen's content, which takes what is
// left. Unbounded, large text grows it past the screen and leaves the content
// no room, so past a third of the screen it scrolls.
class BannerScroll extends StatelessWidget {
  const BannerScroll({super.key, required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height / 3,
    ),
    child: SingleChildScrollView(padding: padding, child: child),
  );
}
