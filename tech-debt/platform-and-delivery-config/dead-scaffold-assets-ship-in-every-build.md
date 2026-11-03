# Placeholder and orphaned assets from flutter create remain tracked in the iOS tree

**Severity:** low

The iOS AppIcon set carries six PNGs for iOS 6-era 50x50, 57x57 and 72x72 slots that Contents.json does not list, so the asset compiler ignores them. All three LaunchImage files are 1x1-pixel stock placeholders and the imageset's README.md is unedited Xcode template text.

## Evidence

- **`ls ios/Runner/Assets.xcassets/AppIcon.appiconset/ | grep -E '50x50|57x57|72x72'`** → `Icon-App-50x50@1x.png\nIcon-App-50x50@2x.png\nIcon-App-57x57@1x.png\nIcon-App-57x57@2x.png\nIcon-App-72x72@1x.png\nIcon-App-72x72@2x.png`
- **`file ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`** → `PNG image data, 1 x 1, 8-bit gray+alpha, non-interlaced`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md:1` — `You can customize the launch screen with your own desired assets by replacing the image files in this directory.`
