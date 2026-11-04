# Six legacy iOS icons that Contents.json omits, and a 1x1 LaunchImage placeholder

**Severity:** low

The iOS AppIcon set carries six PNGs for iOS 6-era 50x50, 57x57 and 72x72 slots that the committed Contents.json does not list, so the asset compiler ignores them. `dart run flutter_launcher_icons` (0.14.4, `ios: true`, no dark or tinted image) regenerates all six and adds them to Contents.json, so deleting them lasts only until the next icon change; removing them for good needs the generator configured for the single-size icon list.

All three LaunchImage files are 1x1-pixel stock placeholders. `LaunchScreen.storyboard` references the image set by name, so it is in use and cannot simply be deleted; replacing it is a brand and launch screen call.

## Evidence

- **`ls ios/Runner/Assets.xcassets/AppIcon.appiconset/ | grep -E '50x50|57x57|72x72'`** → `Icon-App-50x50@1x.png\nIcon-App-50x50@2x.png\nIcon-App-57x57@1x.png\nIcon-App-57x57@2x.png\nIcon-App-72x72@1x.png\nIcon-App-72x72@2x.png`
- **`file ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`** → `PNG image data, 1 x 1, 8-bit gray+alpha, non-interlaced`
- `ios/Runner/Base.lproj/LaunchScreen.storyboard:35` — `<image name="LaunchImage" width="168" height="185"/>`
