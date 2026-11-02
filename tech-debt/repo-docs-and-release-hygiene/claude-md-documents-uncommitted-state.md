# The guidance file is itself untracked and describes an architecture that exists only in this tree

**Severity:** high

`CLAUDE.md` has never been committed. Its Navigation section's activity routes and its entire two-home-tabs section exist only as an uncommitted diff to `main.dart` and `homepage.dart`, and the history, graph, and window providers it describes live in an untracked file alongside four other untracked files those routes and tabs depend on.

It also names `vice_activity_editor_page.dart` among the inline-write sites and lists the window provider as part of the provider chain despite it having no consumer anywhere in `lib/`; it omits `allViceActivityProvider` from the document entirely, despite that provider having no consumer either. A fresh clone receives neither the document nor the code it describes, and a stash or checkout in this same tree would leave a reader oriented against an app that is not there.

## Evidence

- `CLAUDE.md:66` — `` **Navigation.** `main.dart` gates on `userProvider`: null user → `Authenticate`, otherwise `Homepage`. `onGenerateRoute` parses the route as a URI, so `/vices/:viceID/activities` and `/vices/:viceID/activities/:activityID` are matched by path segments ``
- `CLAUDE.md:71` — `` **Two home tabs.** `ViceTracker` shows one day at a time as an `fl_chart` radar chart (`vice_chart.dart`), one axis per unarchived vice. `UsageGraphView` shows one vice over a date range as a line chart ``
- **`git diff -- lib/homepage.dart`** → `-      body: const ViceTracker(),` / `+      body: IndexedStack(...children: const [ViceTracker(), UsageGraphView()],)`
- **`git log --oneline -- CLAUDE.md`** → (no output — the file has no history)
- `CLAUDE.md:46` — `` `manage_data.dart`, `vice_activity_editor_page.dart`, ``
- `CLAUDE.md:51` — `` the history, graph, and window providers depend on `userProvider` alone ``; `allViceActivityProvider` does not appear anywhere in `CLAUDE.md`
- **`grep -rn "allViceActivityProvider\|viceActivityWindowProvider" lib/`** → each name's only match is its own definition in `lib/providers/vice_activity_history_provider.dart`
