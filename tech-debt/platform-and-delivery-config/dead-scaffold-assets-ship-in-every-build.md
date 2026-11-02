# Placeholder and orphaned assets from flutter create remain tracked across three platform trees

**Severity:** low

The iOS AppIcon set carries six PNGs for iOS 6-era 50x50, 57x57 and 72x72 slots that Contents.json does not list, so the asset compiler ignores them. All three LaunchImage files are 1x1-pixel stock placeholders and the imageset's README.md is unedited Xcode template text.

Every Android mipmap density directory holds both the real launcher_icon.png and the stock blue Flutter-logo ic_launcher.png. AndroidManifest.xml's `android:icon="@mipmap/launcher_icon"` wires up the five launcher_icon.png files, but nothing in the tree references ic_launcher.png by name, so those five files are dead. The unqualified launch_background.xml can only be selected below API 21 while the resolved minSdk is 24, so it is unreachable.

## Evidence

- **`ls ios/Runner/Assets.xcassets/AppIcon.appiconset/ | grep -E '50x50|57x57|72x72'`** → `Icon-App-50x50@1x.png\nIcon-App-50x50@2x.png\nIcon-App-57x57@1x.png\nIcon-App-57x57@2x.png\nIcon-App-72x72@1x.png\nIcon-App-72x72@2x.png`
- **`file ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`** → `PNG image data, 1 x 1, 8-bit gray+alpha, non-interlaced`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md:1` — `You can customize the launch screen with your own desired assets by replacing the image files in this directory.`
- **`file android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png`** → `ic_launcher.png: PNG image data, 192 x 192, 8-bit colormap, non-interlaced\nlauncher_icon.png: PNG image data, 192 x 192, 8-bit/color RGBA, non-interlaced`
- `android/app/src/main/AndroidManifest.xml:5` — `android:icon="@mipmap/launcher_icon"`
- **`grep -rn "ic_launcher" android/`** → no matches
- `android/app/src/main/res/drawable/launch_background.xml:4` — `<item android:drawable="@android:color/white" />`
- **`grep -n "val minSdkVersion: Int" .../FlutterExtension.kt`** → `val minSdkVersion: Int = 24`
