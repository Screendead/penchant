# The NOTICES asset ships inside the binary and no screen ever displays it

**Severity:** medium

`pubspec.lock` resolves 134 packages and `lib/` contains no `showLicensePage`, `showAboutDialog`, `LicensePage`, or `AboutDialog` anywhere. Flutter's build tooling still compresses dependency license texts into a NOTICES asset, present in this checkout's build output, so the text ships inside the binary with no UI reading it.

The one navigation entry that exists for it, Settings then About, pushes a route that was never wired up and falls through to the 404 page.

## Evidence

- **`grep -rnE "showLicensePage|showAboutDialog|LicensePage|AboutDialog" lib/`** → (no output — no matches)
- `lib/settings.dart:44` — `title: const Text('About'),`
- `lib/settings.dart:47` — `Navigator.of(context).pushNamed('/settings/about');`
- `lib/main.dart:100` — `case '/settings': return const Settings(); ... default: return const NotFound();`
- **`find build -iname "*notices*"`** → `build/unit_test_assets/NOTICES.Z` / `build/ios/Release-iphoneos/App.framework/flutter_assets/NOTICES.Z`
