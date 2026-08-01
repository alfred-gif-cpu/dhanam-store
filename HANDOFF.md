# Dhanam Store — where things stand (2026-08-01)

Continuation notes. Everything below is deployed and verified against
production unless marked otherwise.

- Live: https://dhanam-store-production.up.railway.app
- Admin panel: `/panel`
- Repo: github.com/alfred-gif-cpu/dhanam-store · local `D:\dhanam_store`
- Railway project: **amusing-kindness** (`1fc7e23e…`). A second project,
  *ingenious-generosity*, exists by accident, builds from the repo root, and
  fails every time — delete it.

---

## What is done

**Security.** A route audit covered all 123 endpoints. Five live holes were
found and closed:

| | was |
|---|---|
| `/auth/firebase-login` | issued a session for any phone number, unverified |
| `/orders/create` | trusted the client's item price |
| `routes_addresses.py` | no auth at all — anyone could read or delete any customer's address |
| `/notifications/send` | unauthenticated push to all ~1,000 devices |
| order status / refund / all-orders | unauthenticated; anyone could refund or list every order |

Also: 7 shadowed duplicate routes deleted (route table now has zero), session
token moved to the Android keystore, `is_active` checked on every request so
blocking a customer takes effect immediately, and Android backup disabled.

**Checkout.** Stock is now reserved atomically on order and returned on
cancel — previously it was never decremented at all. Order ids come from an
atomic counter (the old read-then-increment raced against a unique index and
returned 500s). Quantities capped at 50/line, 100 lines.

**Delivery area.** Orders outside Hosur are refused.
`DELIVERY_PINCODES=["635109","635110","635126"]` covers 26 localities. Add
more by looking up `api.postalpincode.in` (no key needed).

**Search.** Matches a normalised form, so `3roses` finds `3 Roses`. Brand
abbreviations map to real names — `britannia`→`brit`, `colgate`→`col` and
five more — which made ~200 products findable that returned nothing before.
Failed searches are logged: `python scripts/catalog_health.py --search-misses`.

**Images.** 651 → 905 products with photos. 102 MB → 62 MB via
`compress_images.py`, then 254 added from Open Food Facts at full resolution.
Cache headers added, so repeat views cost no network at all.

**Ops.** Uploads persist across deploys (Railway volume at `/data/uploads`),
GitHub Actions checks production every 15 minutes, `backup_db.py` dumps the
database, `.env.example` documents every variable.

---

## Next — Alfred

1. **Play Store submission.** $25 unpaid, no build uploaded. This is the only
   thing between the app and real customers; everything else is polish.
2. **Fix stock levels.** All 2,867 products read 100. That was harmless until
   ordering started decrementing them. Zero out anything not actually stocked,
   via the panel's Inventory section.
3. **FSSAI number and GSTIN.** Neither appears anywhere. The invoice calls
   itself a "Tax Invoice" with no GSTIN on it. Confirm with a CA — this is a
   compliance question, not a code one.
4. **Distributor emails** for the ~1,500 products still without photos. Draft
   and priority order are in `PRODUCT_IMAGES.md`. Free, and covers the branded
   lines no database will.
5. **Atlas M10** (~$9/mo) and **UptimeRobot** before real traffic. M0 will
   throttle during an evening rush.

## Next — Claude

1. **Image attribution screen.** The 254 Open Food Facts photos are CC-BY-SA
   and require visible credit. Needs a Credits screen before Play Store. This
   is an obligation we created, so it should be finished.
2. **258 image proposals awaiting review.** Two sheets:
   - `backend/review.html` — 211 packaged goods
   - `backend/generic_review.html` — 47 loose goods
   Untick wrong ones → *Save approved list* → downloads `approved.txt` → then
   `python scripts/fetch_open_images.py --apply <file>` (or
   `fetch_generic_images.py` for the second). **Do one at a time** — both save
   to the same filename.
3. Optional: AI-generated images for loose goods (needs an API key, ~$12 for
   300), and `--workers` for uvicorn.

---

## Things that cost time, worth not repeating

- **Check for shadowed routes before trusting a fix.** Three separate bugs
  came from editing a duplicate handler that never receives requests. Audit
  with: group `(method, path)` across `main.app.routes` and print any with
  more than one endpoint.
- **`write_text` on Windows turns `"\r\n"` into `"\r\r\n"`.** It silently
  doubled every line in `routes_orders.py`. Use `write_bytes`.
- **Verify a dependency works before shipping a check that needs it.**
  Tightening login broke it in production, because `FIREBASE_CREDENTIALS` was
  malformed. Symptom was a 500 that looked like a code bug.
- **Pace requests to free APIs.** An unpaced image download failed 192 of 254
  times and the failures were caught and skipped silently.
- **Measure before optimising.** PDF invoice generation was flagged as a
  scaling risk; measured at 2–8 ms, it is a non-issue. Conversely, the
  region-migration plan was dropped once it was clear that compressing images
  and adding a cache header did far more for Hosur latency.
