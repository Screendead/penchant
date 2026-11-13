# Weather as an Insights input

The question: should Insights compare your habits with the weather, given that the only free way to get weather means sending a rough location off the phone?

## What exists today

Source: the code and the ideas file.

- Insights compares habits with Apple Health (sleep, heart, activity, workouts, mindful minutes, mood, cycle phase), Calendar and Reminders. Everything is read and worked out on the iPhone.
- The Insights footer says: "Worked out on this device from your journal and Apple Health; Penchant sends none of it anywhere." The Calendar and Reminders permission cards make the same promise ("sends none of it anywhere"). Source: `lib/insights_page.dart`.
- Weather is not built. The ideas file (`ideas/insights/more-data-sources.md`) lists it as blocked. WeatherKit needs a paid Apple developer team. A free outside service "would see a rough location, which breaks 'it stays on your device'; ask Jack before using one."
- Places and daylight are decided and queued. Daylight means sunrise, sunset and day length, worked out on the phone with no network. It comes after places, because it needs the rough location that places provides. Neither is built yet; the handover file says "Next: places".

Taps per log are the same under every option. Weather is looked up by date, not attached to a log.

## Option A: no weather, daylight only

- **What changes:** nothing beyond the daylight work already queued. When it lands, Insights shows daylight findings, for example "On days with under 9 hours of daylight you log Wine 0.8 glasses more" (invented example). See `optionA.html`.
- **Effort:** none extra.
- **Risks:** you miss any pattern that is truly about rain or heat rather than season. In northern latitudes, day length already captures much of the seasonal pattern (inferred, not measured on your data).
- **Day to day:** no new permission and no new card. The privacy promise stays word for word.

## Option B: Open-Meteo, opt-in, area rounded to about 100 km

Open-Meteo is a free weather service. Its historical endpoint needs no key for non-commercial use (https://open-meteo.com/en/docs/historical-weather-api). It has data back to 1940, and the newest 5 days arrive late.

- **What changes:** Insights gets a "Compare with the weather" card, off by default. Tapping it opens a sheet that says exactly what will be sent, with **Turn on weather** and **Not now**. Once it is on, weather findings appear under What sets it off, each with the line "Weather for your area, about 100 km across, from Open-Meteo (CC BY 4.0)". The data licence requires that credit. The footer and the "sends nothing" wording must change to name the one exception. See `optionB.html` for the sheet and a finding.
- **Exactly what leaves the phone** (sources: Open-Meteo's docs and terms, https://open-meteo.com/en/terms):
  - Latitude and longitude rounded to whole degrees: a cell about 111 km north to south, and narrower east to west at UK latitudes, about 70 km.
  - A start date and an end date. Using 1 January of the year your journal starts, rather than the exact first day, avoids revealing when you began.
  - Which weather values to return, for example daily maximum temperature, rain and sunshine hours. With `timezone=auto`, no time zone name is sent.
  - The phone's internet address goes with every request, as with any network call. It can place you more closely than the rounded cell does. Open-Meteo's terms say it may collect IP addresses, that its server logs "may contain sensitive information such as geographical coordinates", and that logs are deleted after 90 days.
  - Requests repeat. One call fills the history, then roughly one a week for the newest days, plus one for each new cell you spend a day in, so travel sends each place you visit at cell size. The weekly top-up is my proposed schedule; the 5-day delay is a fact from the docs.
  - Never sent: habits, entries, times, triggers, Health data, account or user ID. The request carries no Penchant identifier.
- **Effort:** M, about 3 to 4 days. That covers the network client, the opt-in sheet, the cached daily weather (sealed on the phone like the Health store), weather as a daily measure in the engine, the copy changes and tests. This assumes places and daylight have already supplied the rough location (inferred from the queue order).
- **Risks:**
  - **Licence:** the free tier is for non-commercial use only ("You may only use the free API services for non-commercial purposes"). If Penchant is ever sold, or possibly even listed on the App Store, a paid Open-Meteo plan is needed. Its price is not shown on https://open-meteo.com/en/pricing, which was checked. Limits on the free tier are 10,000 calls a day, 5,000 an hour and 600 a minute. Your use would be a few calls a week.
  - **Promise:** it is the first time anything derived from you leaves the device for a third party. It is opt-in, but "nothing leaves the phone" becomes "nothing but this". The journal already syncs to Firebase (habit names and triggers sealed with your key); this would go to a new third party, unsealed.
  - **Quality:** a 100 km cell averages coast and inland and hills and valleys. Rain on a given day may not match where you were. This is inferred and would weaken findings.
  - **Dependency:** a free service can change its terms or go away.
- **Day to day:** one extra permission, the location (shared with places and daylight, inferred), plus this opt-in sheet once. No extra taps per log.

## Option C: wait for a paid team and WeatherKit

- **What changes now:** nothing. Insights looks like option A. Later, with a paid Apple developer team at US$99 a year, Apple Weather supplies the data. WeatherKit is included with membership, at 500,000 calls a month (https://developer.apple.com/weatherkit/). Findings must carry the Apple "Weather" mark and a link to its data sources. See `optionC.html`.
- **Effort later:** M, about 3 days, the same as B but with Apple's client. Effort now: none.
- **Risks:** the location still leaves the phone, to Apple instead of Open-Meteo. Apple says the location "is not associated with any personally identifiable information, and is never tracked between requests". So the footer still has to change; waiting changes who receives the location, not whether it is sent. That the request carries the location is inferred, since a weather lookup needs it. How far back WeatherKit's history reaches is not verified; from memory it is about August 2021.
- **Day to day:** the same as B when it arrives. Nothing until then.

## Recommendation: A, no weather, daylight only

1. Daylight is already being built, needs no network, and covers the seasonal part of what weather would show. Rain or heat on a single day is a weaker, noisier signal at 100 km resolution.
2. "Penchant sends none of it anywhere" is a plain, true promise today. Option B makes it conditional for a modest gain, and an IP address plus a location cell sit in a third party's logs for 90 days.
3. B's free tier is non-commercial only, which is at odds with any future store release, and that price is unknown.
4. C is not better on privacy, only on who receives the location. It is worth revisiting only if a paid team comes for other reasons (WeatherKit, Screen Time, App Attest), and only if daylight findings leave a visible gap.

If nothing is decided, A is what happens: weather stays off the list and daylight ships as planned.
