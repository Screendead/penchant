# Keep the framing neutral, rate the app 18+, and show a disclaimer

**Priority:** release blocker

## What

Apply C16 everywhere: a copy guide (describe, never judge or encourage; never celebrate a higher number or a lower
one; no diagnostic or treatment claims; insights say "goes with", never "causes"), a disclaimer in onboarding and
About ("A personal journal, not medical advice. Talk to a doctor about your health."), and the age rating.

## Decision

Decided by Jack 2026-11-03 (C16): **neutral framing, rated 17+, with a disclaimer.** Harm-reduction framing, support
links and reduction coaching were set aside.

**The 17+ tier no longer exists.** SOURCED: since July 2025 App Store age ratings are 4+, 9+, 13+, 16+ and 18+
([Apple news](https://developer.apple.com/news/?id=ks775ehf)). "Alcohol, Tobacco, or Drug Use or References" rates 13+
when infrequent and 18+ when frequent
([age-rating values](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)),
and a developer may set a higher rating than the questionnaire gives. INFERENCE: a journal of alcohol, nicotine and
drug use has frequent references, so the questionnaire lands at 18+, the nearest tier to Jack's call.

## Why

- SOURCED ([guidelines](https://developer.apple.com/app-store/review/guidelines/) 1.4.3): "Apps that encourage
  consumption of tobacco and vape products, illegal drugs, or excessive amounts of alcohol are not permitted." A
  neutral journal does not encourage, but copy and charts must not read as a score to beat.
- SOURCED (1.4.1): apps that could be used for diagnosis or treatment get greater scrutiny and "should remind users to
  check with a doctor". Health correlations sit close to that line, hence "goes with" wording and the disclaimer.
- SOURCED (register): neutral empty states use the error colour.

## Recommendation

Claude's recommendation: answer the questionnaire honestly (frequent references) and take **18+**, and keep the
reviewer notes short: a personal journal, no encouragement, insights computed on the device.

**Effort:** S (copy guide, disclaimer, questionnaire)

**Revenue impact:** Reduces release risk; a rejection blocks all revenue.

**Depends on:** [positioning](positioning-and-target-user.md); [`neutral-empty-states-use-the-error-colour`](../../tech-debt/accessibility-and-localization/neutral-empty-states-use-the-error-colour.md).

**Needs Jack:** no. 18+ (`r2-age`, Jack, 2026-11-06); the rest waits on a release.
