# Reset information — concepts v2

Status: option A approved for implementation on 23 September 2026.
The user selected A with “Вариант А топ - давай делать”; the complete behavior
is now recorded in `../PRODUCT_SPEC.md`. B remains an unselected alternative.

Prepared: 23 September 2026. The account count, quota percentage and dates in
these drawings are illustrative. The number of available credits is not the
number granted by the illustrated public announcement.

## Visuals

- `reset-info-layouts-v2.svg` / `.png`: A and B at the same 2.2× scale.
- `reset-info-states-v2.svg` / `.png`: independent personal/external states for A.

The drawings extend the existing editable Smooth S visual language. They are
design references, not runtime screenshots. Network settings remain untouched.

## A — personal status first (recommended)

Keep the current narrow, two-column personal quota card. Keep the manual-credit
count in its header and place external announcements in a full-width footer.
For Smooth S with history and one external item, approved card size is
248 × 206 pt (previously 248 × 138); panel 272 × 226 pt. The 68 pt footer has a
source label, a main message and a secondary line. With external forecasts off,
the original card height returns. History off removes its existing 26 pt.

## B — public announcement first

Use the same content with the external band above the personal quota section.
Proposed Smooth S card 320 × 206 pt; panel 344 × 226 pt. The personal ring and
type use the same scale as A; additional width makes the card less compact.
This gives the third-party news more visual priority than the personal state.

## Approved shared semantics

| Personal input | Russian text | English text |
| --- | --- | --- |
| 1 | Ручной сброс: 1 | Manual reset: 1 |
| 2–99 | Ручных сбросов: 3 | Manual resets: 3 |
| 100+ | Ручных сбросов: 99+ | Manual resets: 99+ |
| 0 | Ручных сбросов нет | No manual resets |
| Missing, invalid, disconnected | Нет данных о сбросах | Reset count unavailable |

A positive count means available account credits, not guaranteed ability to
consume one right now. No reset action or consumption probe is included.
The personal count is independent of external opt-in and external failures.

| External state | Russian text | English text |
| --- | --- | --- |
| Opt-out | No external block | No external block |
| First load | Проверяем объявления… | Checking announcements… |
| Successful, no relevant events | Новых объявлений нет | No new announcements |
| Failure | Объявления недоступны / Не удалось обновить источник | Announcements unavailable / Could not refresh source |
| Scheduled regular, future date | Общий сброс · завтра, 09:59 | General reset · tomorrow, 9:59 AM |
| Scheduled regular, no date | Объявлен общий сброс | General reset announced |
| Scheduled time passed | Время прошло; ждём подтверждения | Time passed; awaiting confirmation |
| Scheduled banked | Объявлены ручные сбросы | Manual resets announced |
| Recent latest banked | Сообщают о выдаче ручных сбросов | Manual reset credits reportedly issued |
| Recent latest regular | Сообщают об общем сбросе | General reset reportedly completed |
| Watch with probability | Возможен сброс · ≈60% | Possible reset · ≈60% |
| Watch without probability | Возможен сброс | Possible reset |

Every external block explicitly names Codex Resets. The existing clickable
provider credit stays in the native menu; the hover tooltip remains
noninteractive. A zero personal count plus a public announcement is a valid
combination and never becomes an account-confirmed grant. Failure and a
successful response with no events must be visually distinct.

Implementation note: this proposal assumed the menu credit still existed. The
working tree actually contained its prior deletion. That deletion was preserved
pending the user's answer about restoring it; no link is claimed as implemented.

Show both a scheduled event and a distinct recent latest event when both exist;
do not let the personal count mask either. Approved two-event footer height is
102 pt (34 pt taller than the one-event footer). Show an active watch only when
there is no scheduled event; a distinct recent latest event may remain below.
Deduplicate matching event identifiers. A past scheduled time alone never proves
completion. Consider a `latest_reset` recent for 24 hours from `announced_at`,
not from the fetch time; this is a display policy, not credit expiry. The layout
overview uses the shared public-announcement presentation, not account proof.

## Approved refresh and compatibility

Check on existing triggers and also while the tooltip remains visible, using
the existing visible-tooltip update lifecycle and AppState freshness gate.
Coalesce requests, wait at least 60 seconds between automatic attempts, and
respect longer HTTP cache/retry intervals. Stop view-driven refresh when hidden.
Keep the opt-in, fixed unauthenticated endpoint and in-memory-only data boundary.
An external failure shows unavailable status without affecting personal quota.
No network bypass, PAC/proxy, service, notifications or new dependencies.

Both themes should use the same semantics. Preserve Smooth and Pixel styling,
Standard/Turbo badges, quota colour thresholds, history, Reduce Motion, drag,
hover, pointer passthrough and screen-edge placement. M/L retain their progress
bars; S retains its ring. Pixel and L add the same 68/102 pt footer to the existing
base card; M scales the whole L layout to 80%. VoiceOver reads quota and personal
reset first, then the personal credit count, then the named external source.
It reads the exact count even when the visual label is capped at 99+.

The selected geometry, simultaneous-event layout, recent-event lifetime,
refresh policy and complete RU/EN state behaviour are consolidated in the product
design freeze. Focus verification on simultaneous events,
personal/external independence, opt-out, zero versus unknown, HTTP freshness,
long Russian strings, S/history layout and all screen-edge placements.
