# MaterialApp declares no localization delegates and the app never inspects the device locale

**Severity:** medium

`main.dart`'s `MaterialApp` sets `theme`, `home` and `onGenerateRoute` and never sets `localizationsDelegates` or `supportedLocales`, and `pubspec.yaml` has no `flutter_localizations` dependency; intl alone does not substitute.

The default delegate serves English only, so the resolved locale is pinned to `en`, `Directionality` is always left-to-right, and the framework's own strings inside `showDatePicker` and `showTimePicker`, both used by the editor and the record dialog, render in English on every device. A grep for `localeOf`, `platformDispatcher`, `Platform.localeName` and `defaultLocale` returns nothing, and there is no `l10n.yaml`, no arb file and no `generate: true` under the `flutter:` section of `pubspec.yaml` (the two `generate: true` entries that do exist, at lines 71 and 76, sit under `flutter_launcher_icons:` and control icon generation, not l10n).

## Evidence

- `lib/main.dart:52` — `child: MaterialApp(`
- `lib/main.dart:70` — `home: user == null ? const Authenticate() : const Homepage(),`
- `pubspec.yaml:40` — `intl: ^0.20.3`
- `lib/vice_activity_editor_page.dart:282` — `final DateTime? date = await showDatePicker(`
- **`grep -rn "localeOf\|platformDispatcher\|Platform.localeName\|defaultLocale" lib/`** → (no output — zero matches)
