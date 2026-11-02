# A day with no recorded activities shows a red 'No activities found' box instead of an empty chart

**Severity:** medium

The rewritten `ViceChart` returns a red `InfoBox` whenever the selected day's activity list is empty. The code it replaced tested a map over every activity the user had ever recorded, so the message appeared only for an account with no history at all.

Under the per-day provider the same branch fires for any ordinary day with nothing recorded, so navigating back through history replaces the chart with a red box on every clean day. For a vice tracker a zero day is a good outcome, now indistinguishable from a failure.

## Evidence

- `lib/vice_chart.dart:37` — `if (activityList.isEmpty) {\n      return const InfoBox(\n        message: 'No activities found',\n        color: Colors.red,\n      );\n    }`
- **`git diff lib/vice_chart.dart`** → `-    if (viceActivityListByViceID.isEmpty) {`
