# The res tree has no anydpi-v26 directory or adaptive-icon XML

**Severity:** medium

Only flat legacy PNGs exist per density bucket, and the flutter_launcher_icons config sets a flat image path with no adaptive background or foreground keys, so the generator never emitted one.

On API 26 and later launchers, which apply masking, shape, parallax and shadow treatment uniformly to adaptive icons across installed apps, this app's icon renders as a plain flat square or crop.

## Evidence

- **`find android/app/src/main/res -type d`** → `android/app/src/main/res\nandroid/app/src/main/res/mipmap-mdpi\nandroid/app/src/main/res/mipmap-hdpi\nandroid/app/src/main/res/drawable\nandroid/app/src/main/res/mipmap-xxxhdpi\nandroid/app/src/main/res/mipmap-xxhdpi\nandroid/app/src/main/res/values-night\nandroid/app/src/main/res/values\nandroid/app/src/main/res/drawable-v21\nandroid/app/src/main/res/mipmap-xhdpi` — none of these is an anydpi-v26 adaptive-icon directory either
- `pubspec.yaml:65` — `android: "launcher_icon"`
