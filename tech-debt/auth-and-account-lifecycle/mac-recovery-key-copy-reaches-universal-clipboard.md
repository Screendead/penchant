# On the Mac, a copied recovery key still reaches Universal Clipboard

**Severity:** low

On iOS the recovery key is copied local-only with a 2-minute expiry. macOS has no local-only pasteboard item, so a copy made on the Mac is offered to the user's other Apple devices; the app marks it concealed and transient and clears the Mac's pasteboard after 2 minutes, only while it keeps running. The screen says so rather than claim the copy stays on the device.

## Evidence

- `macos/Runner/MainFlutterWindow.swift` — `SecretPasteboard` writes to `NSPasteboard.general`
- `lib/journal_key/recovery_key_screens.dart` — `RecoveryKeyCopy.copiedOnMac`
