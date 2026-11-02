# background_color and theme_color are 8-digit hex in Flutter's alpha-first order

**Severity:** medium

web/manifest.json sets values in Flutter's alpha-first Dart Color convention with a hash substituted for the 0x prefix, while the Web App Manifest parses 8-digit hex as red-green-blue-alpha. Read to spec they become a near-transparent pale colour at about 7 percent opacity and a pale yellow at about 39 percent rather than the intended opaque near-black and Material pink.

One commit set correct six-digit values and the very next commit, one minute later the same day, changed them to the current form, and pubspec.yaml's launcher-icon web keys carry the same values, so re-running the generator reproduces them.

## Evidence

- `web/manifest.json:6` — `"background_color": "#FF181112",`
- `web/manifest.json:7` — `"theme_color": "#FFE91E63",`
- `pubspec.yaml:73` — `background_color: "#FF181112"`
- **`git show 75d7b9a -- web/manifest.json`** → `-    "background_color": "#E91E63",\n-    "theme_color": "#hexcode",\n+    "background_color": "#181112",\n+    "theme_color": "#E91E63",`
- **`git show 170501b -- web/manifest.json`** → `-    "background_color": "#181112",\n-    "theme_color": "#E91E63",\n+    "background_color": "#FF181112",\n+    "theme_color": "#FFE91E63",`
- **`WebFetch https://developer.mozilla.org/en-US/docs/Web/CSS/hex-color`** → `#RRGGBBAA   // The eight-value syntax`
