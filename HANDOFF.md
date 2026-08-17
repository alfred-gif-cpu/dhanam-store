# Dhanam Store — where things stand (2026-08-17)

Continuation notes. Everything below is deployed and verified against
production unless marked otherwise.

- Live: https://dhanam-store-production.up.railway.app
- Admin panel: `/panel`
- Repo: github.com/alfred-gif-cpu/dhanam-store · local `D:\dhanam_store`
- Railway project: **amusing-kindness** (`1fc7e23e…`). A second project,
  *ingenious-generosity*, exists by accident, builds from the repo root, and
  fails every time — delete it.

Arranged by subject, not by date; `git log` is the chronological view. The two
"Next" lists come first because they are what anyone opening this file
actually needs. **Things that cost time** at the end is the part worth reading
even when nothing is wrong.

---

## Next — Alfred

1. **Play Store submission.** $25 unpaid, no build uploaded. The only thing
   between the app and real customers; everything else is polish.

   Build it with the API URL or it is worse than useless:

   ```
   flutter build appbundle --release --dart-define=API_URL=https://dhanam-store-production.up.railway.app
   ```

   `API_URL` is a compile-time constant. Omit it and the app falls back to
   `10.0.2.2:8000` — the emulator's alias for the build machine — which
   installs perfectly and then times out on every screen, for everyone. That is
   exactly what a test APK built on 2026-08-16 did. Release builds now throw on
   startup instead, so the mistake is loud, but the line above avoids it
   entirely. `appbundle` is what the Play Store takes; `apk` is for installing
   on a phone directly.

2. **Fix stock levels.** Every product reads 100. Harmless until ordering
   started decrementing them. Zero out anything not actually stocked, via the
   panel's Inventory section. Only the 1,107 visible ones matter. The dashboard
   showed it plainly on 2026-08-16: **low stock 0, out of stock 0** across
   2,858 products — the shop believes it has everything. This is the likeliest
   cause of a bad first order.

3. **Copy `backend/backups/uploads-mirror/` off the laptop.** 637 photographs,
   48.9 MB. Until 2026-08-16 they existed only on the Railway volume; now they
   exist there and on one hard disk. A USB stick or Drive folder makes that a
   real backup.

4. **FSSAI number and GSTIN.** Neither appears anywhere, and the invoice calls
   itself a "Tax Invoice" with no GSTIN on it. A CA question, not a code one.

5. **Seven duplicate products, each priced differently.** A customer sees the
   same product twice at two prices, and the stock is split across both
   records. Which price is right is a shop question.

   | | |
   |---|---|
   | `Dds Raw Rice 1kg` | ₹72 and ₹50 |
   | `Navneet Notes` | ₹35 and ₹47 |
   | `Kellog's Muesli With 20% Nuts 240g` ₹182 | `Kelloggs Muesli` ₹51 — *and in a different category* |
   | `Spoon Set` ₹20 | `Spoon-30-50` ₹15 |
   | `Juicer` ₹84 | `Juicer-20-30` ₹70 |
   | `Home Lite` ₹10 | `Homelite Big` ₹10 |

   The last four came from a check worth keeping: group the visible catalogue
   by image *content hash*, then flag any group whose product names start with
   different words. Alfred had given each pair one photograph because they are
   one product. The Kellogg's pair is the one that matters — ₹51 against ₹182
   for what the shared photo says is the same box. (An eighth, a doubled
   `7 Up 20Rs`, Alfred deleted.)

6. **Atlas M10** (~$9/mo) and **UptimeRobot** before real traffic. M0 will
   throttle during an evening rush. Ordering and search are rate-limited, which
   protects M0 from one script but not from genuine evening load.

7. **Photograph the last 114.** Alfred closed most of this gap himself: 631
   visible products had a photo on 2026-08-05, 993 on 2026-08-16. What is left
   is almost entirely `Dds` and `Kr` loose goods, which no distributor and no
   open database has — they need a camera on the counter. The distributor
   drafts in `PRODUCT_IMAGES.md` are worth much less than they were.

8. **What `Dds` and `Kr` stand for** — 148 products of shop shorthand that
   cannot be expanded without knowing.

## Next — Claude

1. **The 258 image proposals are stale — regenerate before using.**
   `backend/review.html` (211 packaged goods) and `backend/generic_review.html`
   (47 loose goods) were built when 542 visible products had no photo. Only 114
   do now, and Alfred's own photograph beats a proposed match, so most of what
   those sheets offer would overwrite good work. Re-run `--propose` against the
   current catalogue. `approved.txt` and `approved_expand.txt` at the repo root
   are left over from earlier rounds and it is not recorded which sheet either
   came from — do not `--apply` them.

2. **Four things the production review found and left alone**, none urgent, in
   the order they will start to matter:
   - Four queries with no limit — `routes_customer.py:245` loads every
     customer, `routes_admin.py:468` and `main.py:680` every matching order,
     `routes_notifications.py:82` a thousand FCM tokens. Fine at today's size;
     orders accumulate forever.
   - `datetime.utcnow()` throughout: deprecated on Python 3.12+, and it returns
     naive datetimes stored as ISO strings, so timestamps carry no timezone.
   - `@app.on_event("startup")` is deprecated; lifespan handlers replaced it.
   - One uvicorn worker, so no headroom if a handler ever blocks.

3. **App Check — after the Play Store listing, not before.** Researched
   2026-08-17 and deliberately deferred. It would be a second, enforced layer
   proving requests come from the real app, on top of the Play Integrity check
   phone auth already does for itself.

   The ordering is the whole point. Play Integrity only grants the
   `PLAY_RECOGNIZED` label to apps published on Google Play, and every build so
   far has been sideloaded — enforcement now would fail attestation on exactly
   the builds used for testing, and the symptom would read as a login bug.
   Enforcement also has a blast radius bigger than the problem: enable it while
   any legitimate path fails and login breaks for everyone at once.

   Sequence: publish → add the code → watch the console's unenforced monitoring
   mode through a week of real logins → enforce. The code is `flutter pub add
   firebase_app_check` plus one call after `Firebase.initializeApp()` in
   `lib/main.dart`, with `AndroidProvider.playIntegrity` in release and
   `AndroidProvider.debug` otherwise — without the debug half, `flutter run`
   and the emulator stop working. Console registration needs the SHA-256 of the
   release keystore. Adding the code early is harmless and starts collecting
   the metrics the enforcement decision needs.

4. **A web build was considered and deliberately dropped.** One codebase —
   `flutter build web` — but all 12 service files use `dart:io`'s `HttpClient`,
   which does not exist in a browser, so they would need moving to
   `package:http` (already a dependency). Login also needs the Railway domain
   in Firebase's authorized domains, and web cannot test push notifications or
   real-device behaviour anyway. Worth doing after launch if customers who will
   not install an app matter; not worth it as a testing convenience while an
   APK exists.

5. Optional: AI-generated images for loose goods (needs an API key, ~$12 for
   300), and `--workers` for uvicorn.

---

## Security and login

A route audit covered all 123 endpoints. Five live holes were found and closed:

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

**Wallet and loyalty, removed.** Deleting the unused screens left six endpoints
with nothing calling them, and three took the customer id from the path without
checking it against the caller's token: any customer could read or spend
another's balance by editing the URL. Same class as the address bug. The
endpoints are gone, which closes it outright rather than adding an ownership
check to code nobody uses. `wallet_balance` and `loyalty_points` stay on the
customer record — the admin customers screen reads them directly. If the
feature returns, the ownership check is the first thing it needs.

**Login costs money per SMS, so sessions are 90 days.** Firebase Phone Auth
bills per OTP. The console shows two meters and one login ticks both: *SMS
Total Sent*, free to **10/day**, and *Phone verification instances — US, Canada
and India*, free to **357/day**. The small one binds, so the eleventh login in
a day is billable. Reported India rates conflict badly between sources — use
*See pricing* in the console, not a blog.

Session length is therefore the dial that sets the bill, and `jwt_expiry_hours`
is 2160 (was 720). A customer needs one SMS a quarter rather than one a month.
It applies only to logins made after the deploy; existing sessions run out on
the old clock.

Long customer sessions are safe here in a way they are not in most apps: the
token is in the Android keystore and `is_active` is checked on every request,
so blocking someone in the panel locks them out at once whatever their token
says. **Admin sessions stay at 24 hours** — set for the opposite reason, since
an admin token opens the panel, every order and every customer record.
`test_tokens.py` asserts both bounds and that they have not converged.

Do not replace Firebase to save this. **The shop is cash on delivery only**
(`payment_method: Literal["cod"]`), so a verified phone number is the only
thing tying an order to a reachable human, and one wasted COD run costs more
than a month of OTPs at this size. Google Sign-In is free and unlimited but
verifies an email, not a number, and accounts are free to make in bulk. An
Indian SMS provider is several times cheaper per message but means rebuilding
the OTP flow — which is where the auth-bypass bug lived before Firebase — plus
DLT registration. Revisit only when the billing page is annoying.

## Orders and delivery

**Checkout.** Stock is reserved atomically on order and returned on cancel —
previously it was never decremented at all. Order ids come from an atomic
counter (the old read-then-increment raced against a unique index and returned
500s). Quantities capped at 50/line, 100 lines.

**Delivery area.** Orders outside Hosur are refused.
`DELIVERY_PINCODES=["635109","635110","635126"]` covers 26 localities. Add more
by looking up `api.postalpincode.in` (no key needed).

**Rate limits and indexes.** `/orders/create` is capped at 10/minute and
`/search` at 60. Ordering was the gap that mattered: stock is reserved the
moment an order is filed, so an unthrottled loop could empty the shelves. The
limiter lives in `rate_limit.py` because importing it from `main` would be a
cycle. Six indexes added, of which `orders.updated_at` and `products.sold_count`
matter most — both are sorted on by paths that run constantly.

## The catalogue: what customers can see

**Trimmed to 1,107 of 2,858** (1,173 of 2,869 when the cut was made; Alfred has
hidden and deleted a few by hand since). `is_active` sat on every product and
was read by nothing, so it hid nothing; browse, search, suggestions, categories
and the home rails now respect it. Absent or true counts as visible — a filter
written `is_active: True` would have emptied the shop for every product
predating the field, silently. Hidden means off the shelf, not withdrawn: a
hidden product still resolves by id and in bulk, so a saved cart or wishlist
does not break and an order for it still goes through.

Two cuts, on different grounds:

- **Movement**, from `Margin_Analysis_May2026.xlsx` — a real till export, 6,309
  products with quantity sold. Kept anything selling 8+ units in May, which is
  93.7% of units in a third of the catalogue. A threshold rather than "top
  1000" because the 1,000th and 1,001st had both sold exactly 8. The 175
  products with no match in the till were **kept**: their names differ there
  (`Brit Nc Digestive 100g` against `BRITNCDIGESTIVE100GM`), which is not
  evidence of no sales.
- **Delivery economics** — Toys & Stationery and Electronics hidden outright,
  189 products, regardless of sales. A ₹10 pen costs the same to deliver as a
  ₹1,000 grocery order and is bought on its own rather than added to a basket.
  The till data cannot see this; it showed stationery selling 1,414 units, more
  than seven other categories.

Still reversible wholesale: `db.products.updateMany({}, {$set: {is_active:
true}})`. Re-run the movement cut against a fresh export when there is one —
May is a single month and says nothing about festival season. The threshold is
one number in the script.

## The catalogue: names and search

**Search** matches a normalised form, so `3roses` finds `3 Roses`. Brand
abbreviations map to real names — `britannia`→`brit`, `colgate`→`col` and five
more — which made ~200 products findable that returned nothing before. Failed
searches are logged: `python scripts/catalog_health.py --search-misses`.

**1,137 products renamed** to one convention: `500g 1kg 750ml 2L 10Rs`, number
and unit joined. Only spacing and unit spelling changed, never a word, so
nothing became unfindable — search counts were identical before and after for
every query checked, and the old spacing still matches because search
normalises spaces away. `search_text` and `search_words` are rebuilt inside the
same update, which matters: a renamed product with stale search fields is
findable only by a name nobody can see. Audit findings fell from 797 to 135.
Re-run `audit_product_names.py` after any bulk import.

**Shorthand expanded, 206 names.** The catalogue was written for someone behind
the counter: `Brit Nc Digestive` is now Britannia NutriChoice Digestive, `Him
Cl Com Br Fc100G` is Himalaya Clear Complexion Brightening Face Cream 100g.

`surf excel` returned **nothing at all** before — the catalogue said `Surf Xl`
and no customer types that; it now finds 13. `front load` also returned
nothing, which matters: front-load and top-load detergents are different
formulations and the wrong one fills a machine with suds. `powder` went 11 to
31, `face wash` 2 to 9. The old shorthand still works, because search
normalises and matches substrings — `brit` finds Britannia.

The rules are context-aware, not a blanket replace, because the same letters
differ by product: `Cl` is Cleaner in a Domex and Clear in the Himalaya line,
`Gin` is Gingelly in an oil and Ginger in a paste, `Mat` is Matic in a
detergent and a floor mat on its own (`Mat-225-250` is a doormat).

Plus 12 plain misspellings: Syrub→Syrup, Gn Oil→Groundnut Oil, Biscuts, Coffe,
Varmicelli, Masla/Masal→Masala. Found by looking for rare words one edit away
from common ones — which also flagged `Parle Milk Shakthi` as a misspelling of
Sakthi. It is a real Parle product. Tamil and regional words score as typos
against an English-weighted comparison, so every candidate was read in context
before being touched.

**`Dds` (135 products) and `Kr` (13) are still shorthand** — the shop's own
prefixes, and nobody outside the shop knows what they stand for. They are
excluded from the expander by name, so re-running it is safe; add them to
`BRANDS` in the script once known.

## Photographs

**993 of the 1,107 visible products have a photo (89.7%)** — 637 uploaded by
hand through the panel, 356 from the earlier imports.

Audited in full on 2026-08-16 against production, and the hand-uploaded set is
sound: every one of the 993 returns 200, no two products share an `image_url`,
and not one upload carries a stale `image_credit`.

The 114 without one are **Bakery & Snacks 22, Spices & Masalas 21**, Rice &
Cereals 15, then Dry Fruits & Nuts and Pulses & Grains at 14 each —
overwhelmingly `Dds` and `Kr` loose goods, which no open database will ever
carry. The distributor route no longer moves this much; a camera does.

18 Unilever photographs came from re-running the importer against one brand at
a lower match bar — `fetch_brand_images.py --brand unilever --min-score 0.5`.
0.75 is right for the whole catalogue, where a loose match pairs a snack with a
lunch box; once the brand is known it is too strict, and "Ponds Dreamflower
Talc" against "Pond's Dream Flower Talcum Powder" scores below it. Roughly 110
Unilever lines still have none.

### Size and compression

The panel stores an upload exactly as it arrived, and a photograph saved from a
manufacturer's site arrives at print resolution — up to 3840px and 4 MB, for
something the app never draws larger than a few hundred pixels. 72 files were
resized to fit 1200px and re-encoded on 2026-08-16: **uploads 65.3 MB → 48.9
MB, the whole visible set 101.7 MB → 85.3 MB**. Harpic Flushmatic alone went
4181 KB → 1151 KB, potato chips 2991 → 170. Run `recompress_uploads.py` after
any batch of hand uploads — 563 of 637 already needed nothing, so most of a
re-run is just checking.

It works against the live volume because the upload endpoint names a file
`slugify(product name) + ext`: re-uploading with the same extension overwrites
the same file, so `image_url` never moves and no saved cart, wishlist or cached
page points anywhere new. The two products renamed *after* their photo was
uploaded are detected and skipped for that reason — they would land on a new
filename and orphan the old file. Originals go to `backend/backups/` first,
since the volume is the only copy that exists.

One upload, `nescafe-classic-25g.png`, arrived with a corrupt `iTXt` metadata
chunk — a half-finished save from the source site. Browsers ignore ancillary
chunk checksums and show it anyway; stricter decoders refuse the whole file.
The script drops the bad chunk without touching a pixel.

### Caching

**Uploads are cached for a week, not five minutes.** They expired in five
because a replacement reuses the same filename and there was no other way to
make the new photograph appear. Cheap when uploads were a few dozen exceptions;
they are now 637 of 993, so nearly every product image cost a round trip every
five minutes of browsing — which for Hosur is most of the perceived load time,
and the exact cost the Cache-Control middleware exists to avoid. It was quietly
undoing the compression above.

`resolve_image_url` stamps upload URLs with the file's mtime, so the URL
changes the moment the photograph does and a week is safe. Both halves have to
hold or the shop serves a week-old photo, so both are tested, and both were
watched to fail: freezing the token, and removing the long header.

Requests with no query string keep the five-minute life — they cannot have come
from `resolve_image_url` and have no way to notice a replacement. The token is
cached for 60 seconds so a product list does not stat a hundred files, and
`save_image` drops the entry it just rewrote, which is the one moment the cache
must not answer from memory.

`fresh()` in the panel appends its own token per render. It predates the
version stamping and is now redundant, but harmless — it already appends `&v=`
when a query exists, and each render is a unique URL, so the admin never sees a
stale thumbnail. Left alone deliberately.

### Attribution

The Open Food Facts photographs are CC-BY-SA and require visible credit. 254
were imported; **193 still carry the credit as of 2026-08-16, and only 9 are on
visible products** — Alfred's uploads replaced most of them. *Profile → Photo
Credits* is filled by `GET /image-credits`, which parses the `image_credit`
string on each product and groups it by source. The licence statement is baked
into the screen rather than fetched, so the credit still appears offline.
**Deploy the backend before shipping an app build**, or the list will not load.

**Replacing a photo clears its credit.** Uploading through the panel sets
`image_url` and unsets `image_credit`. Before this, a shop photograph replacing
an imported one inherited the old credit, so the screen would have attributed
Alfred's own picture to Open Food Facts and published it as CC-BY-SA. The
upload endpoint is the only path that writes `image_url`, so one `$unset`
covers it. That is why the Photo Credits screen is nearly empty now — the
system working, not a bug.

### The only copy problem

**Until 2026-08-16 the photographs existed in one place.** `backup_db.py` dumps
every collection, which preserves the *filename* of each product photo and none
of the pixels — the images themselves lived only on the volume. A detached
volume or a deleted project would have left the catalogue pointing at 637 dead
references with no way back but re-photographing the shop. And this file has
been telling Alfred to go and delete a Railway project.

`backup_uploads.py` mirrors them to `backend/backups/uploads-mirror/` — 637
files, 48.9 MB — with a manifest recording which product, category and
visibility each file belongs to, so a restore knows what it is holding. It
reads the public `/static` path, so it needs no admin token and can alter
nothing. Re-running HEADs each file and fetches only what changed; `--verify`
reports drift without downloading. Every file is opened after fetching, because
a backup nobody has opened is a backup nobody knows works.

It cannot see files the catalogue does not reference — orphans from a rename or
a cleared image. `StaticFiles` does not list directories, so there is no way to
enumerate them from outside, and nothing points at them.

## The admin panel

**Hiding is managed from the panel, not the database.** It was applied by a
script the panel could not see — no badge, no filter, no way back short of a
MongoDB client. It now shows the split on the dashboard (currently `2,858 —
1,107 in the app · 1,751 hidden`), filters the product list by
all/visible/hidden, marks hidden rows, and puts a Hide/Show button on each.
Bringing stationery back in June is: filter to Hidden, search, click Show.
Every toggle lands in the audit log.

The panel lists everything whatever the filter's default — it is the screen a
product gets brought back from, so it has to show what is not on sale. Both the
panel filter and the shop treat a missing flag as visible; if they disagreed
the panel would describe a catalogue customers cannot see.

**The edit form used to open blank past the first hundred products.** It found
its product by fetching `?page=1&limit=100` and searching that list, so
anything later in the alphabet — most of the catalogue — rendered every field
empty, and saving would have written those blanks over the real price, stock,
GST and category. Only the "name is required" check stood in the way. There is
now `GET /admin/products/{id}`, and the form refuses to open rather than
opening blank.

**Image handling.** The edit dialog shows the current photograph (clickable to
full size) so a replacement is chosen with sight of what it replaces, and
`DELETE /admin/products/{id}/image` clears one — a placeholder is honest where
the wrong product is not. The credit leaves with it. The file stays on disk:
unpicking a possibly shared filename is a worse risk than a few unused
kilobytes. List thumbnails are 58px and open full size on click.

## The app

**Legal pages.** Privacy Policy and Terms of Service were written but nothing
linked to them: the only links were in `customer_settings_screen.dart`, which
nothing navigates to. Both are now tiles in *Profile*, alongside Photo Credits.
All of `lib/screens/customer/` was deleted — five screens duplicated live ones,
and wallet and loyalty were dropped as unwanted features.

**Motion is in one place.** `AppMotion` in `lib/theme.dart`, beside
`AppColors`. Entrances on the home greeting and login screen overshoot and
settle (`easeOutBack`), the banner carousel does the same as it advances, and
the wishlist heart and cart quantity — which used to snap with no animation at
all — pop on `elasticOut`. One constant to tune if it is too much.

The rule that is easy to get wrong: **overshoot curves belong on movement,
never on opacity.** `easeOutBack` and `elasticOut` deliberately travel past
their end value, which on an opacity means above 1 or below 0, and Flutter
clamps that — the fade stalls at both ends and the entrance looks broken rather
than lively. So an entrance bounces its slide and eases its fade.
`AppMotion.fade` exists to be the safe one and `test/motion_test.dart` asserts
it stays in range, because a later tidy-up unifying the two curves would
compile, animate, and quietly break every fade in the app.

Both pops are `Transform.scale` on a leaf widget inside the existing gesture
detector. `Transform` takes no part in layout, so no tap target moved and
nothing reflows while the number springs. The ADD ↔ quantity swap was
deliberately *not* wrapped in an `AnimatedSwitcher` for the opposite reason: it
keeps the outgoing button in the tree through the transition, where a stray tap
lands on a button on its way out and adds a second item to the cart. The
checkout `AnimatedContainer`s were left alone too — they animate colour and
borders, an overshoot on a border width can go negative, and colour does not
read as bounce anyway.

**Android minSdk is 24, and the pin at 23 never worked.** This entry used to
say it was pinned at 23 to keep Android 6.0 phones able to install. Every APK
ever built shipped 24.

Flutter runs `MinSdkVersionMigration` on each build, rewriting any literal
`minSdk` of 16–23 to `flutter.minSdkVersion`. The old note assumed an
occasional regeneration was to blame and that a comment in the file would deter
it; it happens on every single build, and a comment cannot stop a regex. Both
APKs built on 2026-08-16 read `minSdkVersion:'24'`.

23 was chosen because `flutter_secure_storage` asks for it, and that is still
the plugin's floor. But Flutter now declares 24 the minimum it supports
(`gradle_utils.dart`, `minSdkVersionInt = 24`), so 23 is below the framework's
floor too. Holding it means dodging the migration's regex — which only matches
a literal, so `val androidMinSdk = 23` then `minSdk = androidMinSdk` survives —
and running under a framework that no longer tests that level. **Alfred's
call**, and it only matters before the Play Store listing fixes the supported
device set.

## Tests, dependencies, ops

**200 tests** — 188 backend, 12 widget — running in CI on every push alongside
`flutter analyze`. They need no database and no network and finish in under a
second, which is the point: a check that fails for reasons unrelated to the
change stops being read. Run with `python -m pytest` in `backend/`, and
`flutter test` at the root.

What they cover is what has actually broken here. The five endpoints found open
in the route audit are asserted closed, anonymously and with a forged token.
Orders are asserted to have no `price` field at all, because the fix for the
tampering bug was removing it from the request shape and a test of the
arithmetic would not notice it returning. The ordering flow runs against
mongomock-motor, a real query engine in process, covering the two properties
only a database can show: stock reserved by conditional update so the last unit
cannot sell twice, and order ids from an atomic counter.

Those sixteen were verified by mutation, not by passing — changing the
reservation to decrement zero fails six of them. Worth repeating for any new
test here: **a suite nobody has watched fail is a suite nobody knows works.**

`widget_test.dart` was not a placeholder, whatever an earlier note implied. It
held six real tests and had been failing to compile since `OtpScreen` dropped
`devOtp` and moved to six digits. Nothing ran them, so nobody knew.

**Dependencies are pinned.** Every requirement used to be a floor, and Railway
installs fresh on each build, so each deploy resolved whatever was newest that
morning. CI ran Starlette 1.3 while this project was developed against 0.52 — a
major version apart, on the library the whole app sits on. `requirements.txt`
now pins the exact set CI passes against, including `starlette` and `pymongo`
explicitly, since they are where the behaviour lives and their parents' floors
allow a major jump. Upgrading is a deliberate act: change a line, let the suite
run, deploy.

**Ops.** Uploads persist across deploys (Railway volume at `/data/uploads`),
GitHub Actions checks production every 15 minutes, `backup_db.py` dumps the
database, `backup_uploads.py` mirrors the photographs, `.env.example` documents
every variable.

---

## How the scripts work

Several scripts propose changes rather than making them, and the pattern is
always the same: run `--propose`, open the HTML it writes **in a real browser**
(the download button does nothing in a preview pane), untick what is wrong,
click *Save approved list*, then run `--apply <file>`.

The saved file lands wherever the browser puts downloads — it has turned up in
`~/Downloads` and in the repo root on different days, so check both. Nothing is
ever applied without one.

| script | proposes |
|---|---|
| `expand_product_names.py` | shorthand expanded into readable names |
| `normalize_product_names.py` | pack sizes to one convention |
| `fetch_brand_images.py` | photographs for one brand at a lower match bar |
| `fetch_open_images.py` | photographs, catalogue-wide |
| `audit_product_names.py` | reports only — duplicates, sizes, abbreviations |

`recompress_uploads.py` is the exception, deliberately: resizing is mechanical,
not a judgement about a particular product, so it reports by default, applies
with `--apply`, and keeps the originals instead of asking anyone to tick 72
boxes. It needs an admin token in `DH_ADMIN_TOKEN` or `backend/.admin_token`
(gitignored) — the panel keeps one in localStorage under `dh_admin_token`.
**Delete that file afterwards; it is a live admin login for 24 hours.** There is
no way to mint one from this repo: `ADMIN_JWT_SECRET` is `settings.jwt_secret +
"-admin"` and production's `JWT_SECRET` lives only in Railway's environment.
That is the security model working, not an obstacle to route around.

---

## Things that cost time, worth not repeating

The recurring shape, worth naming once: **something that cannot fail reads as
safety and provides none.** An assert that asserts `true`, a loop that asserts
only on what it finds, a comment where a constraint was needed. Three separate
entries below are that same bug.

- **Check for shadowed routes before trusting a fix.** Three separate bugs came
  from editing a duplicate handler that never receives requests. Audit with:
  group `(method, path)` across `main.app.routes` and print any with more than
  one endpoint.
- **A guard that cannot fail is not a guard.** `config.dart` fell back to the
  local dev server when `API_URL` was not passed at build time, and a release
  APK built without it reached `10.0.2.2:8000` — an address that means nothing
  off an emulator, so every screen timed out on a real phone. It read as
  guarded: there was an `assert` right there with a message about the fallback.
  The assert tested `true`, so the message could never print, and asserts are
  stripped from release builds regardless. Release builds now throw.
- **A test that can match nothing can pass vacuously.** A test's
  public-endpoint half iterated routes and asserted only on what it found — so
  on a newer Starlette it would have reported success while checking zero
  endpoints. Worse than no test. If a check loops before it asserts, assert on
  the count too.
- **The config is not the artifact.** `build.gradle.kts` said `minSdk = 23`,
  the comment above it explained why, and this file repeated the claim for
  months. Every APK shipped 24, because Flutter rewrites that line on every
  build. Nobody had ever read a built APK. Where a toolchain can rewrite your
  input, the output is the only evidence — `aapt2 dump badging` here, and the
  same reasoning as reading the served image rather than the database row.
- **Do not test a framework's internals.** A test walked FastAPI's route table
  to check each protected endpoint carried an auth guard. It passed locally and
  failed in CI, because CI resolved a newer Starlette that arranges routes
  differently, and two attempts to fix it were two attempts to make a fragile
  thing work. The 28 tests that simply send a request and check for a 401 never
  wavered. Ask the app; do not read it.
- **"Works locally" is a claim about one machine.** Local was fastapi 0.135 and
  starlette 0.52; CI resolved 0.141 and 1.3 from the same requirements file.
  Three CI runs went into discovering that. Deps are pinned now, but after any
  change to them, `pip install -r requirements-dev.txt` locally or the gap
  reopens.
- **Verify a dependency works before shipping a check that needs it.**
  Tightening login broke it in production, because `FIREBASE_CREDENTIALS` was
  malformed. The symptom was a 500 that looked like a code bug.
- **Look at the output, not just the numbers.** The compression pass reported
  4181 KB → 1151 KB and zero failures. Rendering a before-and-after strip and
  actually looking at it showed transparent PNGs coming out ringed in black:
  resampling averages colour and alpha separately, and where a pixel is fully
  transparent there is no colour left to average, so the white hidden behind it
  became black. Composited on the app's white card both look identical — the
  damage only appears when something *flattens* the image instead (a share
  sheet, a PDF, a thumbnailer). A summary of byte counts cannot show that. The
  fix is in `whiten_transparency`.
- **A flag is not a finding.** Every audit written here over-reported on its
  first run — 51 wrong-brand flags of which 4 were real, 10 "hands" that were
  brown packaging, 350 unit "errors" that were only a house style not yet
  chosen. Calibrate against a sample and count the false positives before
  believing the number, or the tool becomes noise that gets ignored.
- **A photo saved from a website is not a product photograph.** Alfred's 637
  uploads were sound, but the workflow leaves fingerprints worth checking after
  any batch: 29 were the small preview off a results page rather than the image
  behind it (`candle.webp` is 180×180), one carried a corrupt metadata chunk
  from a half-finished save, and 119 were at print resolution. None of it shows
  in the panel, which renders everything at 58px.
- **Check whether the thing is already correct before processing it.** A
  background-whitening pass was run over the catalogue and made it worse,
  because 343 of 778 photographs were already on white and a cutout can only
  damage those. The best edit to something already right is none.
- **Pace requests to free APIs.** An unpaced image download failed 192 of 254
  times and the failures were caught and skipped silently.
- **Match brand names as whole words.** The same bug landed twice in one
  session: `(?<![a-z])a|b|c(?![a-z])` binds the lookarounds to only the first
  and last alternative, so every brand between them matched mid-word — "rin"
  inside "Drink", "Bru" inside "Brunch", "lux" inside "Deluxe", "fanta" inside
  "Fantasy". Group the alternation: `(?:...)`.
- **A find-and-replace that matches nothing should be an error.** Patching the
  panel by script, one of four edits silently did not match: the Hide button was
  never added while the function it calls was. The page would have loaded
  perfectly and simply had no button. Caught by counting occurrences after — do
  that, or edit by hand.
- **A form that fails to load its data must not open.** The panel's edit dialog
  fetched the first hundred products and searched that list for the one clicked.
  Past the first hundred it found nothing, kept the empty template it started
  with, and rendered every field blank — and saving would have written those
  blanks over a real product. Failing loudly beats degrading into something that
  looks usable.
- **A capability with no controls is a trap.** 1,651 products were hidden by a
  script, and the panel showed no badge, no filter and no way to undo it — the
  only route back was a MongoDB client. Whoever inherits that has a shop they
  cannot fully explain or reverse. Ship the switch with the wiring.
- **The numbers cannot see the business.** The catalogue cut was argued from
  till data, and the data said keep stationery: 1,414 units in May, more than
  seven other categories. Alfred removed it anyway, because a ₹10 pen costs the
  same to deliver as a ₹1,000 grocery order and nobody adds a pen to a grocery
  basket. Sales volume measures what sells over a counter, not what is worth
  driving to a house. Ask before arguing with the shopkeeper.
- **Measure before optimising.** PDF invoice generation was flagged as a
  scaling risk; measured at 2–8 ms, it is a non-issue. Conversely, the
  region-migration plan was dropped once it was clear that compressing images
  and adding a cache header did far more for Hosur latency.
- **`write_text` on Windows turns `"\r\n"` into `"\r\r\n"`.** It silently
  doubled every line in `routes_orders.py`. Use `write_bytes`.
