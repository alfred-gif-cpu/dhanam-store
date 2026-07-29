# Getting official product images

The clean white-background photos on Blinkit, Zepto and BigBasket are not
theirs — they are supplied by the brands, who make them available to retailers
precisely so their products look right on shelf and online. As a retailer
selling genuine stock, you can request the same files.

Three routes, best first.

---

## 1. GS1 India DataKart — the national product registry

Indian brands upload official product data and images to **DataKart**, run by
GS1 India. It is the system the large retailers pull from, and it is built for
exactly this: a retailer needs correct images and pack details for products it
stocks.

- Site: https://www.gs1india.org / https://www.datakart.org
- Ask for: retailer/subscriber access for a grocery store
- Covers: most barcoded national FMCG brands
- Cost: paid subscription; ask for their smallest retailer tier

**This is the closest thing to "give me the Blinkit images" that is legitimate.**

Worth doing early, because it also gives you barcodes — and with barcodes,
image matching stops being guesswork. Every automated attempt so far has had to
match on product *names*, which is why some proposals were wrong.

---

## 2. Ask your distributors directly — free, start today

Every distributor you already buy from has a marketing or trade-support contact
who can send a product image pack. This costs nothing and often arrives within
a week. Draft below.

Priority order, based on how much of the catalogue each covers:

| Brand family | Products in catalogue |
|---|---|
| Britannia ("Brit ...") | 55 |
| Himalaya ("Him ...") | 46 |
| Gillette ("Gil ...") | 32 |
| Sakthi ("Sak ...") | 32 |
| Colgate ("Col ...") | 12 |
| Parle ("Par ...") | 16 |
| Yardley ("Yard ...") | 16 |

Also worth contacting: Aachi, Annai, MTR, Dabur, Nivea, Ponds/HUL, Cavins,
Arun, Milky Mist, Lion Dates, 777, Doms, Cello.

### Email to send

> **Subject:** Request for product images — Dhanam Store, Hosur (retail partner)
>
> Dear [Distributor / Brand] team,
>
> I run Dhanam Store, a grocery retailer in Hosur, Tamil Nadu. We stock and
> sell [Brand] products, and we are launching a mobile ordering app for our
> customers.
>
> Could you share your product image pack for the [Brand] range we carry —
> the standard white-background product photographs used for online retail?
> Front-of-pack images at web resolution are ideal.
>
> I am happy to confirm in writing that the images will be used solely to
> display [Brand] products we genuinely stock, within our own store app, and
> not modified or passed on to third parties.
>
> If there is a portal or media library I should register for instead, please
> point me to it.
>
> Our GST number and store details are below for verification.
>
> Thank you,
> Alfred
> Dhanam Store, Hosur
> [phone] · [email] · [GST number]

Two things make this land: say you **stock the product**, and offer the usage
undertaking up front. That is the reassurance a brand's trade team needs.

---

## 3. Photograph the rest yourself

Local and unbranded lines — loose grains, appalam, house-brand packs — will
never be in any database. Around 1,600 products fall here.

What makes shop photos look professional:

- **White background.** A sheet of white A3 paper curved up the wall behind
  works; no visible edge or crease line.
- **Daylight, indirect.** Near a window, not in direct sun. No flash — it
  blows out packaging and casts hard shadows.
- **Same setup every time.** Consistency across the grid matters more than
  any single photo being perfect.
- **Straight on, pack filling the frame**, a little margin around it.
- **Nothing else in shot** — no hands, price stickers, shelf edges.

Batch it: 30–40 products in a session, same spot, same light. Then drop the
files into `backend/static/images/` named as in `photo-worklist.csv` and run:

```
python scripts/bulk_update_images.py
python scripts/compress_images.py --apply
```

---

## Where things stand

- 651 products already had photos
- ~254 added from Open Food Facts (CC-BY-SA — credit required in the app)
- ~1,600 still need images, mostly Personal Care, Household and local brands

Routes 1 and 2 are the ones that produce Blinkit-quality results. Route 3 is
for what no one else has photographed.
