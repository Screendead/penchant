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

// Whether [text] wraps into [maxLines] lines of [maxWidth] without being cut.
bool chartLabelWraps(
  BuildContext context,
  String text,
  TextStyle style, {
  required double maxWidth,
  required int maxLines,
}) {
  final TextPainter painter = _layOut(
    context,
    text,
    style,
    maxLines: maxLines,
    maxWidth: maxWidth,
  );
  final bool fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

// fl_chart lays a radar title out on one line with no width limit, so the
// string itself must fit in [maxWidth]: [suffix] is dropped first, then
// [name] is cut short with an ellipsis, and when not even an ellipsis fits the
// label is empty. [nameWhole] is false whenever the name is not shown in full.
({String text, bool nameWhole}) fitChartLabel(
  BuildContext context, {
  required String name,
  required String suffix,
  required TextStyle style,
  required double maxWidth,
}) {
  bool fits(String text) =>
      chartLabelSize(context, text, style).width <= maxWidth;

  if (fits('$name$suffix')) {
    return (text: '$name$suffix', nameWhole: true);
  }
  if (fits(name)) {
    return (text: name, nameWhole: true);
  }
  if (!fits('…')) {
    return (text: '', nameWhole: false);
  }

  final Characters characters = name.characters;
  int low = 0;
  int high = characters.length - 1;
  while (low < high) {
    final int mid = (low + high + 1) ~/ 2;
    if (fits('${characters.take(mid)}…')) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return (
    text: '${characters.take(low).toString().trimRight()}…',
    nameWhole: false,
  );
}
