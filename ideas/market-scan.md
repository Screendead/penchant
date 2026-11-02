# Market scan: vice and habit trackers

*Dated 2026-11-02. Method: web search snippets, plus one fetch of Apple's App Review Guidelines page, which gave verbatim text.* Markers: **SOURCED** comes from those results, **INFERENCE** is reasoning, and **UNVERIFIED** is a claim that was not checked against a primary source. Sources disagree on prices, so treat every price as indicative and check the live App Store listing before using it.

## Direct competitors

| App | Model (SOURCED, indicative) | Ratings and complaints (SOURCED) |
|---|---|---|
| **I Am Sober** (sobriety counter and community) | The core tracker and the community are free. Plus is reported at $9.99/mo or $39.99/yr with a 7-day trial; Lifetime at $64.99–69.99; 12-month plans at $23.99–49.99 (UK £29.99–37.99). | About 4.9★ from about 173K iOS ratings. The top complaint is a paywall on basic features (about 10% of users, per one summary), plus emotionally intense community posts. |
| **Reframe** (alcohol reduction, coaching and content) | Reported at $13.99/mo (Access) and $19.99–24.99/mo (Silver), with a $100/yr web plan. Pricing is described as "personalized". | 4.8★ from more than 18K reviews. Main complaint: a 7-day trial that converts to an annual plan. Rated BBB F on 8 billing complaints (refunds mostly granted), with unanswered support emails and Trustpilot apologies for unclear pricing. UNVERIFIED: a 2026 data breach with 3 lawsuits. |
| **Sunnyside** (mindful drinking, AI coach) | 15-day trial, then Basic at $8.25 (billing period not stated). Raised $11.5M; TechCrunch covered its AI coach launch (2023). | — |
| **Quitzilla** (generic quit tracker) | The free tier tracks 2 habits. Premium is $5.99/mo, $29.99/yr, $24.99 for 6 months or $89.99 lifetime. | Users say you can only have 2 habits unless you subscribe. |
| **MyDrinkaware** (UK charity) | Free. Tracks units, calories, drink-free days and spend; some listings say sleep too. | The developer has acknowledged complaints that a redesign removed old tracking features. |
| **Generic habit trackers** (secondary blogs; figures conflict) | Streaks: one-time $4.99–5.99, with a habit cap reported as 12 or 24. Way of Life: $4.99 one-time, or free with a $29.99 lifetime option. Habitify: $2.49–4.99/mo, with 3 free habits. Habitica: free, with Premium cosmetics at about $4.99/mo. | — |

The scan found nothing on "Less".

## Patterns

- SOURCED: capping free users at 2–3 habits is the standard paywall in generic trackers.
- SOURCED: lifetime purchases in the sobriety apps sit around $65–90.
- SOURCED: the biggest complaints are aggressive paywalls, trials that convert to annual plans unexpectedly, and support that is hard to reach.
- INFERENCE: the other apps either cover alcohol only (Reframe, Sunnyside, MyDrinkaware) or count days abstinent (quit trackers). The scan found no mainstream app that logs quantities across several vices with a radar view, but the search was not exhaustive.
- INFERENCE: three models fit the evidence:
  - a one-time or lifetime unlock, which avoids the billing complaints;
  - a cheap subscription with a clear trial;
  - a free tier capped at 2–3 vices.
- INFERENCE: positioning on those complaints would be "no dark-pattern billing, private data, works offline".

## App Store Review Guidelines (verbatim where quoted)

Source: <https://developer.apple.com/app-store/review/guidelines/>

- **1.4.1 Medical:** "Medical apps that could provide inaccurate data or information, or that could be used for diagnosing or treating patients may be reviewed with greater scrutiny." Such apps "should remind users to check with a doctor".
- **1.4.3 Substances:** "Apps that encourage consumption of tobacco and vape products, illegal drugs, or excessive amounts of alcohol are not permitted. Apps that encourage minors to consume any of these substances will be rejected." I Am Sober and MyDrinkaware both list 17+, which is evidence for the rating, not a rule.
- **3.1.1:** unlocking features requires in-app purchase.
- **3.1.2(a):** an auto-renewable subscription "must provide ongoing value". It must last at least 7 days and be available on all of the user's devices.
- **3.1.2(c):** describe clearly what the user gets before asking them to subscribe.
- **4.2 Minimum functionality:** an app must be more than a repackaged website.
- **5.1.1 (login):** if an app lacks significant account-based features, let people use it without a login.
- **5.1.1(v):** "If your app supports account creation, you must also offer account deletion within the app." Deletion must not be unnecessarily difficult. Sources: <https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion>, <https://developer.apple.com/support/offering-account-deletion-in-your-app>.
- **5.1.2(i):** get permission before sharing personal data with third parties, including third-party AI.
- **5.1.3 Health data:** health data must not be used for advertising, marketing or data mining.

## Gaps

The scan did not cover:

- the last 14K characters of the guidelines page, which include 5.1.1(i) on privacy policies and the privacy nutrition labels;
- primary pricing pages for Reframe, I Am Sober, Quitzilla or Streaks;
- direct Reddit or review text beyond what summaries quote;
- Google Play policy, and EU or UK regulation of alcohol apps;
- conversion benchmarks, and RevenueCat pricing.

## Sources

- I Am Sober: <https://apps.apple.com/app/id672904239>, <https://www.choosingtherapy.com/i-am-sober-app-review/>, <https://apppricinglab.com/app/apple/672904239>
- Reframe: <https://www.choosingtherapy.com/reframe-app-cost/>, <https://de.trustpilot.com/review/reframeapp.com>, <https://www.healthline.com/health/mental-health/reframe-app-review>
- Sunnyside: <https://www.sunnyside.co/>, <https://techcrunch.com/2023/11/15/mindful-drinking-app-sunnyside-lands-11-5m-to-launch-its-ai-powered-coach/>
- Quitzilla: <https://apps.apple.com/us/app/quitzilla-quit-tracker/id1533076568>, <https://quitzilla.com/>
- MyDrinkaware: <https://www.drinkaware.co.uk/tools/mydrinkaware-app>, <https://apps.apple.com/gb/app/mydrinkaware-alcohol-tracker/id901389586>
- Habit trackers: <https://toolradar.com/tools/streaks/pricing>, <https://toolradar.com/tools/habitify/pricing>, <https://habitdoom.com/blog/best-habit-tracker-iphone-2026>
