# Codex reset watch — design exploration

Status: **implemented; full headless test suite passed, live service smoke pending**
Prepared: 16 September 2026
Approved: 16 September 2026 — tooltip option B, opt-in off by default
Refined: 21 September 2026 — personal reset-credit confirmation

## Product distinction

The existing tooltip already shows the exact planned reset of the current
account window from Codex App Server `resetsAt`. Codex Resets describes a
different event: a public, account-independent extra reset announcement or an
AI-classified forecast based on public posts. The two must never share a label,
timestamp, freshness state, or error state.

Sources: [site](https://codex-resets.com/),
[API docs](https://codex-resets.com/api/docs), and
[OpenAPI](https://codex-resets.com/api/openapi.json).

## Recommended first slice

Show an approaching **extra Codex reset** only while the hover tooltip is open.
Replace only the otherwise generic left-hand title in the existing header:

| API state | RU header | EN header |
| --- | --- | --- |
| active watch with chance | `СБРОС? ≈60%` | `RESET? ≈60%` |
| active watch without chance | `ЕСТЬ СИГНАЛ` | `RESET WATCH` |
| scheduled, time known | `СБРОС · 18:00` | `RESET · 6 PM` |
| scheduled, time unknown | `СБРОС ОБЪЯВЛЕН` | `RESET ANNOUNCED` |
| scheduled time passed | `ЖДЁМ ПОДТВ.` | `AWAITING CONF.` |
| scheduled banked credit | personal confirmation mapping below | personal confirmation mapping below |
| no signal or external error | existing title | existing title |

The percentage, Standard/Turbo badge, progress, personal reset countdown,
history, panel dimensions, pointer and placement remain unchanged. `?`, `≈`,
`объявлен` / `announced`, and the orange forecast color carry meaning; color is
not the only cue. No new animation is added.

The persistent badge in the pet's top-right transparent area remains an
alternative, not the recommendation: it is glanceable, but competes with
absorbable-object paths and the alpha-based hover/drag/pass-through region. A
new tooltip row is clearer but adds 24–28 pt of height and expands every edge,
size and history layout.

## Visual prototypes

- [Tooltip placement options](../concepts/reset-watch-tooltip-options-v1.png)
- [Smooth/Pixel and API states](../concepts/reset-watch-recommended-states-v1.png)
- [Worst-case Smooth S prototype](../concepts/reset-watch-tooltip-small-v1.png)
- [Persistent pet-badge alternative](../concepts/reset-watch-pet-badge-v1.png)

## Truth and state rules

1. `scheduled_reset` has priority over an active watch.
2. `active_watch` is visible only before its `expires_at`. `expires_at` is the
   forecast expiry, never the predicted reset time.
3. A passed `scheduled_for` does not prove execution; show “awaiting
   confirmation” until the API reports a completed reset or removes the item.
4. `reset_type: banked` is a reset credit, not an automatically applied regular
   reset.
5. Unknown enums, invalid dates, out-of-range probabilities, an oversized body,
   an unexpected final host, or an incompatible schema fail closed.
6. `latest_reset`, aggregate stats, source post text/URL, history, and the
   free-text `forecast_window` are deferred from the first slice.

The status snapshot generated at `2026-09-15T22:07:09.845Z` reported the latest
regular reset at `2026-09-12T08:09:17Z` and no active watch or scheduled reset.
That means the current UI would remain unchanged.

## Network and privacy boundary

The current product promises local processing. This feature adds a third-party
HTTPS request and therefore exposes ordinary network metadata such as IP address
and User-Agent to codex-resets.com. The recommended policy is a persisted
opt-in, off by default; choosing documented default-on behavior requires an
explicit product decision and privacy-copy change.

The client sends only unauthenticated `GET https://codex-resets.com/api/v1/status`
with no query, body, cookies, account ID, quota, plan, history, project data,
locale, or Codex credentials. It respects `Cache-Control`, `ETag`/`304`, and
`Retry-After`; requests are coalesced and occur on start after opt-in, wake, and
tooltip open only when cached data is stale. No polling timer, backend,
dependency, raw-response persistence, or forecast history is added.

Timeout, `429`, `503`, malformed data, or expiry hides only the external signal.
It never changes Codex connection state, personal quota, history, reconnect,
pet opacity, or `Retry Now`. A last-good signal may remain in memory only until
its own expiry.

Direct access to the service timed out from the design and implementation
environment; the schema and snapshot were retrieved through a read-only text
proxy. The client is covered by deterministic transport tests, while a direct
live-service smoke remains pending until the environment can reach the host.

## Accessibility and compatibility

- The tooltip remains noninteractive and adds no keyboard stop.
- VoiceOver reads personal quota/reset first, then a separate sentence naming
  codex-resets.com as a third-party forecast and explicitly saying it is not the
  personal reset time.
- Reduce Motion is fully static.
- Smooth/Pixel, Standard/Turbo, S/M/L, English/Russian, history on/off, missing
  or stale personal quota, all four placements, screen edges, drag, absorption,
  click-through, fullscreen hiding and Codex-only visibility keep their current
  behavior.
- The representative layout gate is Smooth S, Russian, Turbo, history on, with
  `СБРОС? ≈60%`; it must fit the existing 272 × 158 pt history panel.

## Deferred

macOS notifications, sound, flashing, source links, raw announcement text,
last-reset history, statistics, custom forecasting, advice to spend quota,
applying banked credits, secondary quota, and duplicating the signal across the
tooltip, pet, Pixel context menu and menu bar.

## Approved decisions

1. Use tooltip option B: replace only the generic header while a valid signal
   exists.
2. Require a persisted opt-in that is off by default. The first slice exposes
   it as a native menu toggle; no request occurs before it is enabled.
3. Use the compact RU/EN copy above, including explicit forecast markers and
   banked-reset wording.
4. Do not add the signal or its setting to the pet surface, custom context menu,
   or a Settings window in the first slice.

## Approved personal reset-credit refinement

The App Server response already read by the app can include the authoritative
earned-reset count at `rateLimitResetCredits.availableCount`. This personal
account state supersedes the ambiguous visual phrase `СБРОС В ЗАПАС` while the
third-party banked value remains only an announcement.

| App Server | Public banked announcement | Header |
| --- | --- | --- |
| `availableCount == 1` | any/off | `РУЧНОЙ СБРОС: 1` / `MANUAL RESET: 1` |
| `availableCount` from 2 through 99 | any/off | `РУЧНЫХ СБРОСОВ: %d` / `MANUAL RESETS: %d` |
| `availableCount >= 100` | any/off | `99+ СБРОСОВ` / `99+ RESETS` |
| `availableCount == 0` | active | `АНОНС · СБРОСА НЕТ` / `ANNOUNCED · NO RESET` |
| absent, `null`, invalid, or disconnected | active | `АНОНС · НЕИЗВЕСТНО` / `ANNOUNCED · UNKNOWN` |
| zero or unknown | absent | ordinary title |

A positive count confirms an available credit, not that an eligible window can
definitely be reset at that moment. Never call the mutating consume operation as
a check. The count stays memory-only, requires no new request or opt-in, clears
to unknown with the App Server connection, and never enters quota history or a
Codex Resets request.

The confirmed personal state is gold and has priority over external reset-watch
states. Announcement-only states remain orange and explicitly textual. Panel
geometry and all existing Smooth/Pixel, S/M/L, Standard/Turbo, history, Reduce
Motion, and placement behavior remain unchanged. Applying the credit and all
controls remain deferred.

The compact high-count policy was approved on 22 September 2026: values through
99 remain exact; 100 and above render as `99+ СБРОСОВ` / `99+ RESETS` so the
smallest one-line tooltip cannot truncate. VoiceOver always reads the exact
count.

Representative prototype:
[`confirmed-manual-reset-v1.png`](../concepts/confirmed-manual-reset-v1.png).

The consolidated freeze is recorded in `PRODUCT_SPEC.md`. The original
reset-watch implementation matches its separately authorized first-slice
boundary. The separately authorized personal confirmation refinement is now
implemented through the existing App Server read and shared tooltip semantics.
