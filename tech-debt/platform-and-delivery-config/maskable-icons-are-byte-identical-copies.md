# The two maskable PWA icons have no safe-zone padding

**Severity:** low

web/manifest.json lists maskable 192 and 512 icons alongside the plain ones, and md5 checksums show each maskable file is byte-identical to its plain counterpart. A platform applying an adaptive mask, such as Android's circular or squircle shapes, crops straight into the artwork instead of a padded safe zone.

## Evidence

- `web/manifest.json:22` — `{\n            "src": "icons/Icon-maskable-192.png",\n            "sizes": "192x192",\n            "type": "image/png",\n            "purpose": "maskable"\n        },`
- **`md5 /Users/jacklusher/development/tracker/web/icons/*.png`** → `MD5 (Icon-192.png) = bf62289337dbef605802fe82f3b9cd4c\nMD5 (Icon-maskable-192.png) = bf62289337dbef605802fe82f3b9cd4c\nMD5 (Icon-512.png) = 1098230d33752ed744362c5dd6ba96f9\nMD5 (Icon-maskable-512.png) = 1098230d33752ed744362c5dd6ba96f9`
