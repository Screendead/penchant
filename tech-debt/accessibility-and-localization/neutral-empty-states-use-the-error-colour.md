# InfoBox renders no-data-yet states in the same danger red as real failures

**Severity:** low

`InfoBox` is used both for genuine problems and for plain empty-data states such as "no vices found", "no activities found" and "no vices available to graph", and every call site passes the same red.

A first-time user who has not added a vice sees the identical red-on-red treatment as any real error, with colour the only cue distinguishing nothing-here-yet from something-broke.

## Evidence

- `lib/vice_chart.dart:31` — `return const InfoBox(\n        message: 'No vices found',\n        color: Colors.red,\n      );`
- `lib/usage_graph_view.dart:80` — `return const InfoBox(\n        message: 'No vices available to graph',\n        color: Colors.red,\n      );`
