# The iOS LaunchImage is a 1x1 placeholder

**Severity:** low

All three LaunchImage files are 1x1-pixel stock placeholders. `LaunchScreen.storyboard` references the image set by name, so it is in use and cannot simply be deleted; replacing it is a brand and launch screen call.

## Evidence

- **`file ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`** → `PNG image data, 1 x 1, 8-bit gray+alpha, non-interlaced`
- `ios/Runner/Base.lproj/LaunchScreen.storyboard:35` — `<image name="LaunchImage" width="168" height="185"/>`
