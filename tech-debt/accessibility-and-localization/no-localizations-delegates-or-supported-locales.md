# English is the only language, and every UI string is a literal in its widget

**Severity:** low

The localization delegates are in place but the app supports one locale, `en`, so `Localizations` resolves to English on every device and the framework's own strings (date and time pickers, tooltips) are English everywhere.

The app's own copy is hard-coded string literals in the widgets: there is no `l10n.yaml`, no arb file and no `generate: true` under `flutter:` in `pubspec.yaml`, so adding a language means extracting every string first. Dates and numbers already follow the device's region through `lib/formats.dart`; words and their plural rules are English by design there.

## Evidence

- `lib/formats.dart:6` — `const List<Locale> appLocales = [Locale('en')];`
- `lib/main.dart:71` — `supportedLocales: appLocales,`
- `lib/bootstrap.dart:64` — `supportedLocales: appLocales,`
- **`grep -rn "Text('" lib/ | wc -l`** → 42 literal `Text` widgets, besides labels, tooltips and messages built from string literals
