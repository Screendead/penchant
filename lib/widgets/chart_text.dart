import 'package:flutter/material.dart';

TextPainter _layOut(
  BuildContext context,
  String text,
  TextStyle style, {
  int maxLines = 1,
  double maxWidth = double.infinity,
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: DefaultTextStyle.of(context).style.merge(style),
  ),
  textDirection: TextDirection.ltr,
  textScaler: MediaQuery.textScalerOf(context),
  maxLines: maxLines,
)..layout(maxWidth: maxWidth);

// fl_chart reserves a fixed extent for axis titles; this measures what a
// label needs at the device's text scale so it is not clipped.
Size chartLabelSize(BuildContext context, String text, TextStyle style) {
  final TextPainter painter = _layOut(context, text, style);
  final Size size = painter.size;
  painter.dispose();
  return size;
}
