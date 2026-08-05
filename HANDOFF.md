# Dhanam Store — where things stand (2026-08-02)

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

**Catalogue trimmed to 1,175 of 2,871.** `is_active` sat on every product and
was read by nothing, so it hid nothing; browse, search, suggestions,
categories and the home rails now respect it. Absent or true counts as
visible — a filter written `is_active: True` would have emptied the shop for
every product predating the field, silently. Hidden means off the shelf, not
withdrawn: a hidden product still resolves by id and in bulk, so a saved cart
or wishlist does not break and an order for it still goes through.

Two cuts, on different grounds:

- **Movement**, from `Margin_Analysis_May2026.xlsx` — a real till export,
  6,309 products with quantity sold. Kept anything selling 8+ units in May,
  which is 93.7% of units in a third of the catalogue. The threshold rather
  than "top 1000" because the 1,000th and 1,001st had both sold exactly 8.
  The 175 products with no match in the till were **kept**: their names differ
  there (`Brit Nc Digestive 100g` against `BRITNCDIGESTIVE100GM`), which is not
  evidence of no sales.
- **Delivery economics** — Toys & Stationery and Electronics hidden outright,
  189 products, regardless of sales. A ₹10 pen costs the same to deliver as a
  ₹1,000 grocery order and is bought on its own rather than added to a basket.
  The till data cannot see this; it showed stationery selling 1,414 units,
  more than seven other categories.

**Managed from the panel, not the database.** Hiding was applied by a script
and the panel could not see it — no badge, no filter, no way back short of a
MongoDB client. It now shows `2,871 — 1,175 in the app · 1,696 hidden` on the
dashboard, filters the product list by all/visible/hidden, marks hidden rows,
and puts a Hide/Show button on each. Bringing stationery back in June is:
filter to Hidden, search, click Show. Every toggle lands in the audit log.

The panel still lists everything whatever the filter's default — it is the
screen a product gets brought back from, so it has to show what is not on
sale. Both the panel filter and the shop treat a missing flag as visible; if
they disagreed the panel would describe a catalogue customers cannot see.

Still reversible wholesale if wanted:
`db.products.updateMany({}, {$set: {is_active: true}})`. Re-run the movement
cut against a fresh export when there is one — May is a single month and says
nothing about festival season. The threshold is one number in the script.

**Replacing a photo clears its credit.** Uploading through the panel sets
`image_url` and now unsets `image_credit`. Before this, a shop photograph
replacing an imported one inherited the old credit, so the Photo Credits
screen would have attributed Alfred's own picture to Open Food Facts and
published it as CC-BY-SA. The upload endpoint is the only path that writes
`image_url`, so one `$unset` covers it.

**Tests.** 176 of them — 169 backend, 7 widget — running in CI on every push
alongside `flutter analyze`. They need no database and no network and finish
in under a second, which is the point: a check that fails for reasons
unrelated to the change stops being read. Run with `python -m pytest` in
`backend/`, and `flutter test` at the root.

What they cover is what has actually broken here. The five endpoints found
open in the route audit are asserted closed, anonymously and with a forged
token. Orders are asserted to have no `price` field at all, because the fix
for the tampering bug was removing it from the request shape and a test of
the arithmetic would not notice it returning. The ordering flow runs against
mongomock-motor, a real query engine in process, covering the two properties
that only a database can show: stock reserved by conditional update so the
last unit cannot sell twice, and order ids from an atomic counter.

Those sixteen were verified by mutation, not by passing — changing the
reservation to decrement zero fails six of them. Worth repeating for any new
test here: a suite nobody has watched fail is a suite nobody knows works.

`widget_test.dart` was not a placeholder, whatever an earlier note implied.
It held six real tests and had been failing to compile since `OtpScreen`
dropped `devOtp` and moved to six digits. Nothing ran them, so nobody knew.

**Rate limits and indexes.** `/orders/create` is capped at 10/minute and
`/search` at 60. Ordering was the gap that mattered: stock is reserved the
moment an order is filed, so an unthrottled loop could empty the shelves.
The limiter lives in `rate_limit.py` because importing it from `main` would
be a cycle. Six indexes added, of which `orders.updated_at` and
`products.sold_count` are the ones that matter — both are sorted on by paths
that run constantly.

**Dependencies are pinned.** Every requirement used to be a floor, and
Railway installs fresh on each build, so each deploy resolved whatever was
newest that morning. CI ran Starlette 1.3 while this project was developed
against 0.52 — a major version apart, on the library the whole app sits on.
`requirements.txt` now pins the exact set CI passes against, including
`starlette` and `pymongo` explicitly, since they are where the behaviour
lives and their parents' floors allow a major jump. Upgrading is now a
deliberate act: change a line, let the suite run, deploy.

**Ops.** Uploads persist across deploys (Railway volume at `/data/uploads`),
GitHub Actions checks production every 15 minutes, `backup_db.py` dumps the
database, `.env.example` documents every variable.

---

## Next — Alfred

1. **Play Store submission.** $25 unpaid, no build uploaded. This is the only
   thing between the app and real customers; everything else is polish.
2. **Fix stock levels.** Every product reads 100. That was harmless until
   ordering started decrementing them. Zero out anything not actually stocked,
   via the panel's Inventory section. Only the 1,175 visible ones matter —
   hiding the rest cut this job by more than half.
3. **FSSAI number and GSTIN.** Neither appears anywhere. The invoice calls
   itself a "Tax Invoice" with no GSTIN on it. Confirm with a CA — this is a
   compliance question, not a code one.
4. **Distributor emails** for the ~1,500 products still without photos. Draft
   and priority order are in `PRODUCT_IMAGES.md`. Free, and covers the branded
   lines no database will.
5. **Atlas M10** (~$9/mo) and **UptimeRobot** before real traffic. M0 will
   throttle during an evening rush. Ordering and search are rate-limited now,
   which protects M0 from one script but not from genuine evening load.
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
2. **Four things the production review found and left alone**, none of them
   urgent, in the order they will start to matter:
   - Four queries with no limit — `routes_customer.py:245` loads every
     customer, `routes_admin.py:468` and `main.py:680` every matching order,
     `routes_notifications.py:82` a thousand FCM tokens. Fine at today's
     size; orders accumulate forever.
   - `datetime.utcnow()` throughout: deprecated on Python 3.12+, and it
     returns naive datetimes stored as ISO strings, so the timestamps carry
     no timezone.
   - `@app.on_event("startup")` is deprecated; lifespan handlers replaced it.
   - One uvicorn worker, so no headroom if a handler ever blocks.
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
- **A capability with no controls is a trap.** 1,651 products were hidden by
  a script, and the panel showed no badge, no filter and no way to undo it —
  the only route back was a MongoDB client. Whoever inherits that has a shop
  they cannot fully explain or reverse. Ship the switch with the wiring.
- **A find-and-replace that matches nothing should be an error.** Patching the
  panel by script, one of four edits silently did not match: the Hide button
  was never added while the function it calls was. The page would have loaded
  perfectly and simply had no button. Caught by counting occurrences after —
  do that, or edit by hand.
- **The numbers cannot see the business.** The catalogue cut was argued from
  till data, and the data said keep stationery: 1,414 units in May, more than
  seven other categories. Alfred removed it anyway, because a ₹10 pen costs
  the same to deliver as a ₹1,000 grocery order and nobody adds a pen to a
  grocery basket. Sales volume measures what sells over a counter, not what
  is worth driving to a house. Ask before arguing with the shopkeeper.
- **Do not test a framework's internals.** A test walked FastAPI's route
  table to check each protected endpoint carried an auth guard. It passed
  locally and failed in CI, because CI resolved a newer Starlette that
  arranges routes differently, and two attempts to fix it were two attempts
  to make a fragile thing work. The 28 tests that simply send a request and
  check for a 401 never wavered in either environment. Ask the app; do not
  read it.
- **A test that can match nothing can pass vacuously.** The same test's
  public-endpoint half iterated routes and asserted only on what it found —
  so on the newer Starlette it would have reported success while checking
  zero endpoints. Worse than no test. If a check loops before it asserts,
  assert on the count too.
- **"Works locally" is a claim about one machine.** Local was fastapi 0.135
  and starlette 0.52; CI resolved 0.141 and 1.3 from the same requirements
  file. Three CI runs went into discovering that. Deps are pinned now, but
  after any change to them, `pip install -r requirements-dev.txt` locally or
  the gap reopens.
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
