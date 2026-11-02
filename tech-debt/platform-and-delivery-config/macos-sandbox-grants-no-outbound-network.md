# Both entitlements files enable the sandbox without the network client entitlement

**Severity:** medium

DebugProfile.entitlements and Release.entitlements both set the app-sandbox entitlement and neither declares network.client; the debug file instead declares network.server, which covers the inbound Flutter VM-service connection and grants no outbound access.

firebase_auth and cloud_firestore require outbound HTTPS, which macOS blocks at the OS level under those entitlements.

## Evidence

- `macos/Runner/Release.entitlements:5` — `<key>com.apple.security.app-sandbox</key>\n\t<true/>`
- `macos/Runner/DebugProfile.entitlements:9` — `<key>com.apple.security.network.server</key>\n\t<true/>`
