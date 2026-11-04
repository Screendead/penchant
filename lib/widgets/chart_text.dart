import 'package:flutter/material.dart';

// fl_chart reserves a fixed extent for axis titles; this measures what a
// label needs at the device's text scale so it is not clipped.
Size chartLabelSize(BuildContext context, String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final Size size = painter.size;
  painter.dispose();
  return size;
}

// fl_chart lays a radar title out on one line with no width limit, so the
// string itself must fit: [name] is cut short with an ellipsis until
// [name] + [suffix] fits in [maxWidth]. The suffix is kept whole; when even
// an ellipsis and the suffix are too wide, as on a radar with dozens of axes,
// the label is left whole, since cutting it would not make it fit.
String fitChartLabel(
  BuildContext context, {
  required String name,
  required String suffix,
  required TextStyle style,
  required double maxWidth,
}) {
  bool fits(String text) =>
      chartLabelSize(context, text, style).width <= maxWidth;

  if (fits('$name$suffix') || !fits('…$suffix')) {
    return '$name$suffix';
  }

  final Characters characters = name.characters;
  int low = 0;
  int high = characters.length - 1;
  while (low < high) {
    final int mid = (low + high + 1) ~/ 2;
    if (fits('${characters.take(mid)}…$suffix')) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return '${characters.take(low).toString().trimRight()}…$suffix';
}
