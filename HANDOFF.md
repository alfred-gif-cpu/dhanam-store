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

**Images.** 651 → 923 products with photos. 102 MB → 62 MB via
`compress_images.py`, then 254 added from Open Food Facts at full resolution.
Cache headers added, so repeat views cost no network at all.

A further 18 Unilever photographs came from re-running the importer against
one brand at a lower match bar — `fetch_brand_images.py --brand unilever
--min-score 0.5`. 0.75 is right for the whole catalogue, where a loose match
pairs a snack with a lunch box; once the brand is known it is too strict, and
"Ponds Dreamflower Talc" against "Pond's Dream Flower Talcum Powder" scores
below it. Roughly 110 Unilever lines still have no photo, and the open
databases have nothing for them — that gap needs the distributor.

**Names.** 1,137 products renamed to one convention: `500g 1kg 750ml 2L
10Rs`, number and unit joined. Only spacing and unit spelling changed, never
a word, so nothing became unfindable — search counts were identical before
and after for every query checked, and the old spacing still matches because
search normalises spaces away. `search_text` and `search_words` are rebuilt
inside the same update, which matters: a renamed product with stale search
fields is findable only by a name nobody can see. Audit findings fell from
797 to 135. Re-run `audit_product_names.py` after any bulk import.

**Image attribution.** The 254 Open Food Facts photographs are CC-BY-SA and
require visible credit. *Profile → Photo Credits* now shows it, filled by
`GET /image-credits`, which parses the `image_credit` string recorded on each
product and groups it by source. The licence statement itself is baked into
the screen rather than fetched, so the credit still appears offline. **Deploy
the backend before shipping an app build**, or the list will not load.

**Legal pages.** Privacy Policy and Terms of Service were written but nothing
in the app linked to them: the only links were in `customer_settings_screen.dart`,
which nothing navigates to. Both are now tiles in *Profile*, alongside Photo
Credits. All of `lib/screens/customer/` was deleted — five screens duplicated
live ones, and wallet and loyalty were dropped as unwanted features.

**Wallet and loyalty, removed.** Deleting the screens left six endpoints with
nothing calling them, and three of those took the customer id from the path
without checking it against the caller's token: any customer could read or
spend another's balance by editing the URL. Same class as the address bug.
The endpoints are gone, which closes it outright rather than adding an
ownership check to code nobody uses. `wallet_balance` and `loyalty_points`
stay on the customer record — the admin customers screen still displays them,
reading the fields directly. If the feature ever returns, the ownership check
is the first thing it needs.

**Android minSdk.** Pinned at 23, not `flutter.minSdkVersion`. Flutter 3.44
defaults to 24, and regenerating `android/app/build.gradle.kts` silently
reverts to it, dropping Android 6.0 phones. 23 is what `flutter_secure_storage`
requires for the keystore-backed session token, and the highest any plugin
asks for — the minimum that builds and the widest device support available.
The reasoning is in the file so the next regeneration does not undo it.

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
6. **Three duplicate products, two priced differently.** `Dds Raw Rice 1kg`
   at ₹72 and ₹50; `Navneet Notes` at ₹35 and ₹47; `7 Up 20Rs` twice at ₹20.
   The names are now identical, so a customer sees the same product twice at
   two prices, and the stock is split across both records. Which price is
   right is a shop question — say, and the merge takes a minute.
7. **Three photographs show the wrong product.** `Sunfeast Cheese 50` shows a
   Deutsche Grammophon CD sleeve, `Canaan 20-30` shows a moving company
   invoice, `Arun Ic 10` shows a Pepsi pack. Found by OCR against the product
   name; the script is in `650d180` if the check is ever wanted again.

## Next — Claude

1. **258 image proposals awaiting review.** Two sheets:
   - `backend/review.html` — 211 packaged goods
   - `backend/generic_review.html` — 47 loose goods
   Untick wrong ones → *Save approved list* → downloads `approved.txt` → then
   `python scripts/fetch_open_images.py --apply <file>` (or
   `fetch_generic_images.py` for the second). **Do one at a time** — both save
   to the same filename.
   `approved.txt` at the repo root is left over from one of these and it is
   not recorded which — check before running `--apply` on it.
2. Optional: AI-generated images for loose goods (needs an API key, ~$12 for
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
- **Match brand names as whole words.** The same bug landed twice in one
  session: `(?<![a-z])a|b|c(?![a-z])` binds the lookarounds to only the first
  and last alternative, so every brand between them matched mid-word — "rin"
  inside "Drink", "Bru" inside "Brunch", "lux" inside "Deluxe", "fanta"
  inside "Fantasy". Group the alternation: `(?:...)`.
- **Check whether the thing is already correct before processing it.** A
  background-whitening pass was run over the catalogue and made it worse,
  because 343 of 778 photographs were already on white and a cutout can only
  damage those. The best edit to something already right is none.
- **A flag is not a finding.** Every audit written here over-reported on its
  first run — 51 wrong-brand flags of which 4 were real, 10 "hands" that were
  brown packaging, 350 unit "errors" that were only a house style not yet
  chosen. Calibrate against a sample and count the false positives before
  believing the number, or the tool becomes noise that gets ignored.
- **Measure before optimising.** PDF invoice generation was flagged as a
  scaling risk; measured at 2–8 ms, it is a non-issue. Conversely, the
  region-migration plan was dropped once it was clear that compressing images
  and adding a cache header did far more for Hosur latency.
