# Five DateFormat call sites pass a pattern and no locale, and initializeDateFormatting is never called

**Severity:** medium

`Intl.defaultLocale` is never set and `initializeDateFormatting`, required before formatting in any locale other than intl's compiled-in fallback, is never called anywhere in `lib/`.

Every rendered date and time is therefore fixed to the `en_US` fallback regardless of device locale, and none of the five sites uses a locale-aware skeleton constructor such as `yMd` or `Hm`; all five are hardcoded literal patterns.

## Evidence

- `lib/vice_tracker.dart:114` — `DateFormat('EEEE, MMMM d, yyyy').format(date);`
- `lib/usage_graph_view.dart:125` — `final DateFormat labelFormat = DateFormat('MMM d');`
- `lib/vice_activity_history_page.dart:60` — `'${vice.unit.label(activity.quantity)} on ${DateFormat('EEE, MMM d, yyyy • HH:mm').format(createdAt)}',`
- `lib/vice_activity_editor_page.dart:28` — `static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');`
- `lib/widgets/record_new_activity_dialog.dart:13` — `static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');`
- **`grep -rn "initializeDateFormatting" lib/`** → (no output — zero matches)
