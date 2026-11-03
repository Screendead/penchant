# Harden the backend before strangers can install the app

**Priority:** release blocker

## What

The rules rewrite (PR #27) is live in production since 2026-11-03, and queue item 1b added the quantity, name-length
and vice-ownership checks. Option B below was built in PR #55.

Done (PR #55):

- every activity query is bounded: the day and graph queries by their date window, history by 50-entry pages, the
  editor by its one document, Manage Data by a server-side `count()`; the day query's new index is in
  `firestore.indexes.json`;
- every query is keyed on the signed-in uid, so the previous user's data no longer shows after a sign-out;
- the client activates App Check (App Attest with the DeviceCheck fallback; the debug provider on the emulators),
  enforced nowhere.

Left before strangers install:

- **The vice lists are unbounded.** Whether to cap the number of vices per user is the open call `vice-cap`
  (`HANDOVER.md`, "Calls waiting on Jack").
- **App Check yields no accepted token on a device yet.** The App Attest entitlement can't be signed by the personal
  team, so App Attest has nothing to attest with. The DeviceCheck fallback does not cover this: in
  `firebase_app_check` 0.4.5+2 (`FirebaseAppCheckPlugin.swift`, `appAttestWithDeviceCheckFallback`) the plugin picks
  App Attest on the OS version alone (`if #available(iOS 14.0, macOS 14.0, *)`), so DeviceCheck never runs on a
  current device. Fixing it needs the paid Apple Developer Program team, then the entitlement, the App Check
  registration in the console, and enforcement once nearly all requests verify.
- **Budget alerts** on the production project.

The last two are console and Apple tasks for Jack, listed under "For Jack to do" in `HANDOVER.md`; the entitlement
itself is Claude's once the paid team exists.

Health and calendar data never reach Firestore (see the [insights engine](../insights/insights-engine.md)), so the
backend holds only the user's own logs.

## Why

- SOURCED (register, before PR #55): every list query streamed unbounded data, which grows the read bill and the
  cold-start time with every year of history a journal user builds.
- INFERENCE: a privacy-positioned journal survives a bug, not a breach or a runaway bill.

## Options

- **A.** Bounded queries only.
- **B.** A, plus App Check. Read the current Firebase App Check docs for Flutter on Apple platforms first.
- **C.** B, plus per-user write-rate limits in the rules.

## Recommendation

Claude's recommendation: **B**, plus budget alerts, which cost nothing. Built in PR #55 apart from what is listed as
left above. On `vice-cap`, Claude recommends leaving the vice lists unbounded for 1.0.

**Effort:** M (S left: the entitlement, once the paid team exists)

**Revenue impact:** Avoids risk.

**Depends on:**
- [`vice-lists-are-unbounded`](../../tech-debt/firebase-data-layer/vice-lists-are-unbounded.md)
- The paid Apple Developer Program team (also needed by the [iOS release pipeline](ios-release-pipeline-and-testflight.md))

**Needs Jack:** yes — `vice-cap`; the paid team; the App Check console steps and budget alerts.
