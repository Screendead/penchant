# Frame the app as harm reduction so it clears App Store guidelines 1.4.1 and 1.4.3

**Priority:** release blocker

## What

Set the app's stance and apply it everywhere. That covers a copy guide (non-judgemental, never celebrating a higher number, no diagnostic or treatment claims), a "not medical advice; talk to a doctor" line in onboarding and About, an optional "Get support" screen with region-appropriate helplines (alcohol, gambling, smoking), and the age rating. The core visual should change too: today the radar plots raw daily quantity per vice (`lib/vice_chart.dart`), so more consumption draws a bigger shape.

## Why

- SOURCED ([Apple guidelines](https://developer.apple.com/app-store/review/guidelines/), 1.4.3): "Apps that encourage consumption of tobacco and vape products, illegal drugs, or excessive amounts of alcohol are not permitted. Apps that encourage minors to consume any of these substances will be rejected."
- SOURCED (1.4.1): apps that could be used for diagnosis or treatment get greater scrutiny and "should remind users to check with a doctor".
- SOURCED: I Am Sober and MyDrinkaware both list 17+. That is evidence for the rating, not a rule.
- INFERENCE: a reviewer could read a radar that grows with consumption as a high score. Plotting quantity against a user-set limit turns it into a harm-reduction view.

## Options

- **A. Neutral tool:** a disclaimer and 17+ only, with the chart unchanged.
- **B. Harm-reduction framing:** a disclaimer, 17+, support links and the copy guide. The radar is plotted against each vice's limit (a ring at 100%) once [per-vice goals](../v1-must-haves/per-vice-goals-and-limits.md) exist, and under-limit days are highlighted.
- **C. Full reduction coaching** (Reframe and Sunnyside territory): content, programmes and check-ins. Much bigger scope and more 1.4.1 scrutiny.

## Recommendation

Claude's recommendation, not a decision: **B.** It removes the 1.4.3 risk from the core visual without making medical claims, and it gives the radar a meaning beyond totals. The copy guide, disclaimer, support screen and age rating are blockers. The limit-relative radar arrives with per-vice goals in the same 1.0.

**Effort:** M

**Revenue impact:** It reduces release risk, since a rejection blocks all revenue. It also creates the feature a paid tier builds on.

**Depends on:** [positioning](positioning-and-target-user.md); [per-vice goals and limits](../v1-must-haves/per-vice-goals-and-limits.md); [`neutral-empty-states-use-the-error-colour`](../../tech-debt/accessibility-and-localization/neutral-empty-states-use-the-error-colour.md).

**Needs Jack:** yes — Neutral tracker or reduction tool, which age rating, and should the app link to helplines?
