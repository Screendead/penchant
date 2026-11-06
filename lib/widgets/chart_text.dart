import 'package:flutter/material.dart';

TextPainter _layOut(
  BuildContext context,
  InlineSpan text, {
  int maxLines = 1,
  double maxWidth = double.infinity,
}) => TextPainter(
  text: TextSpan(style: DefaultTextStyle.of(context).style, children: [text]),
  textDirection: TextDirection.ltr,
  textScaler: MediaQuery.textScalerOf(context),
  maxLines: maxLines,
)..layout(maxWidth: maxWidth);

// fl_chart reserves a fixed extent for axis titles; this measures what a
// label needs at the device's text scale so it is not clipped.
Size chartLabelSize(BuildContext context, String text, TextStyle style) {
  return chartSpanSize(context, TextSpan(text: text, style: style));
}

// The same for a span of several styles.
Size chartSpanSize(BuildContext context, InlineSpan text) {
  final TextPainter painter = _layOut(context, text);
  final Size size = painter.size;
  painter.dispose();
  return size;
}
