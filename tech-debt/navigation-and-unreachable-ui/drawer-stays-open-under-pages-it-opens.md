# Pages opened from the drawer leave the drawer open behind them

**Severity:** low

The drawer's Manage Data and Settings tiles push their route without closing the drawer first. Closing the page returns the user to the home screen with the drawer still open over it, so every visit to a drawer page costs an extra tap on the scrim to get back to the chart.

The end-to-end helpers work around it: after closing a drawer page they wait for the drawer to be hit-testable and tap beside it, and the helper's comment records the behaviour as how the app currently works.

## Evidence

- `lib/homepage.dart:50` — `onTap: () {\n                Navigator.of(context).pushNamed('/manage-data');\n              },`
- `lib/homepage.dart:57` — `onTap: () {\n                Navigator.of(context).pushNamed('/settings');\n              },`
- `integration_test/support.dart:189` — `// The drawer stays open under a page pushed from it; dismiss both, as a user\n// would, by closing the page and tapping the scrim beside the drawer.`
