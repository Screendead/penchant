# Radar titles and ticks use fixed font sizes painted outside the widget tree

**Severity:** medium

`ViceChart` sets its title and tick text styles to fixed 14 and 10 point sizes for text fl_chart paints internally through its own `TextPainter`, outside the reach of a `MediaQuery` text scaler.

A user who has raised their device's accessibility text size still gets the same labels on the one screen where label legibility matters most for a low-vision reader.

## Evidence

- `lib/vice_chart.dart:94` — `color: theme.colorScheme.secondary,\n            fontSize: 14,`
- `lib/vice_chart.dart:118` — `color: theme.colorScheme.secondary,\n            fontSize: 10,`
