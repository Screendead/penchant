# Unit labels hand-roll two-category pluralisation and quantities never pass through NumberFormat

**Severity:** low

`nameFor` selects between exactly two forms on a count-equals-one test, the correct rule only for English-like languages, while intl, already a direct dependency, provides plural and ICU message support that nothing in `lib/` references.

Every quantity is shown or written back through plain string interpolation or `toString`, with no `NumberFormat` call anywhere, so there is no grouping or locale-digit support; for the small integer counts stored today the output happens to look identical in every locale.

## Evidence

- `lib/data/unit.dart:15` — `String nameFor(int count) => count == 1 ? singular : plural;`
- `lib/data/unit.dart:16` — `String label(int count) => '$count ${nameFor(count)}';`
- `pubspec.yaml:42` — `intl: ^0.20.3`
- `lib/vice_activity_history_page.dart:62` — `subtitle: Text('Quantity: ${activity.quantity}'),`
- `lib/vice_activity_editor_page.dart:47` — `quantityController.text = activity.quantity.toString();`
- **`grep -rn "NumberFormat" lib/`** → (no output — zero matches)
