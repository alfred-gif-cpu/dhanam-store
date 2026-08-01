"""Find inconsistencies and mistakes in product names.

The name is the product, as far as a customer is concerned. It is what they
search, what they read on the card, and what they check against the packet
when it arrives. It is also the only field here that no import script can
repair, because there is nothing to compare it against.

Two kinds of problem, and they are worth separating:

  mistakes        the same product entered twice, a size that contradicts
                  itself, an empty or nonsense name. These cost money —
                  duplicates split stock across two records so both look
                  in stock when neither is, and a search finds one of them.

  inconsistencies "500 G" beside "500g" beside "500Gm". Each one is fine
                  alone; together they make the catalogue read as though
                  nobody is looking after it, and they make search harder
                  than it needs to be.

Nothing is renamed here. Renaming is a decision per product, and a bad rename
is worse than an ugly name — a customer searching for what they saw last week
should still find it.

    python scripts/audit_product_names.py

Writes name_issues.csv, and name_issues.html grouped by kind of problem.
"""
import asyncio
import collections
import csv
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from database import products_collection  # noqa: E402

CSV_OUT = Path("name_issues.csv")
HTML_OUT = Path("name_issues.html")

# Every way the catalogue spells each unit, mapped to one form. Used to decide
# whether two names describe the same pack, not to rewrite anything.
UNIT_CANON = {
    "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g",
    "kg": "kg", "kgs": "kg", "ml": "ml", "l": "l", "lt": "l", "ltr": "l",
    "litre": "l", "rs": "rs", "pc": "pc", "pcs": "pc", "pkt": "pkt",
}
SIZE = re.compile(r"(\d+(?:\.\d+)?)\s*([a-zA-Z]{1,5})\b")
RUN_ON = re.compile(r"[a-zA-Z]{3,}(\d+(?:\.\d+)?)\s*(g|kg|ml|l|gm|lt|ltr|rs)\b", re.I)


def canon(name: str) -> str:
    """A comparable form of a name: same product, same string."""
    s = re.sub(r"[^a-z0-9]+", " ", (name or "").lower())

    def unit(m):
        num, u = m.group(1), m.group(2).lower()
        return f"{num}{UNIT_CANON.get(u, u)}"

    s = SIZE.sub(unit, s)
    return " ".join(s.split())


def check(name: str) -> list[str]:
    issues = []
    raw = name or ""

    if not raw.strip():
        return ["empty name"]
    if raw != raw.strip():
        issues.append("leading or trailing space")
    if "  " in raw:
        issues.append("double space")
    if len(raw.strip()) < 4:
        issues.append("very short name")
    if not re.search(r"[a-zA-Z]", raw):
        issues.append("no letters in name")

    # "Everyday Milk Bread450G" — the size welded onto the last word. Reads
    # badly on a card and splits the word for search.
    if RUN_ON.search(raw):
        issues.append("size joined to word")

    units = [m.group(2) for m in SIZE.finditer(raw)]
    canon_units = {UNIT_CANON.get(u.lower(), u.lower()) for u in units}
    weights = canon_units & {"g", "kg"}
    volumes = canon_units & {"ml", "l"}
    # "3 Roses 500G 2Kg" — two weights in one name, so which is it?
    if len(weights) + len(volumes) > 0 and len([u for u in units
                                                if UNIT_CANON.get(u.lower(), u.lower()) in
                                                {"g", "kg", "ml", "l"}]) > 1:
        issues.append("more than one size")

    # Unit spelling is deliberately not flagged per product. "Rs" is not a
    # mistake, and neither is "Kg" — the catalogue simply uses several forms
    # of each. That is one decision to make once, reported as a summary
    # below, not 350 individual faults to wade through.

    if re.search(r"[^\w\s.\-&()+/'%,]", raw):
        issues.append("unusual punctuation")
    if re.search(r"\b[A-Z]{4,}\b", raw):
        issues.append("shouty word")
    # Two or more stubs like "Ch", "Cr", "Com" — the name has been abbreviated
    # past the point a customer can read it.
    stubs = [w for w in re.findall(r"[A-Za-z.]+", raw)
             if 1 < len(w.replace(".", "")) <= 3 and w.lower() not in
             {"and", "the", "for", "with", "no", "kg", "ml", "gm", "rs", "pc", "ice", "oil", "tea"}]
    if len(stubs) >= 3:
        issues.append("heavily abbreviated")

    return issues


async def main() -> None:
    products = []
    async for p in products_collection.find({}, {"name": 1, "category": 1, "price": 1}):
        products.append(p)
    print(f"checking {len(products)} product names\n")

    rows = []
    for p in products:
        name = p.get("name") or ""
        for issue in check(name):
            rows.append({"kind": issue, "name": name, "category": p.get("category", ""),
                         "price": p.get("price", ""), "id": str(p["_id"])})

    # Same canonical form, more than one record: the same product entered
    # twice. Sizes are part of the key, so a 200g and a 500g stay separate.
    groups = collections.defaultdict(list)
    for p in products:
        groups[canon(p.get("name") or "")].append(p)
    dupes = {k: v for k, v in groups.items() if len(v) > 1 and k}

    for key, members in dupes.items():
        for m in members:
            rows.append({"kind": "duplicate product", "name": m.get("name", ""),
                         "category": m.get("category", ""), "price": m.get("price", ""),
                         "id": str(m["_id"])})

    # How each unit is actually spelled across the catalogue, so the choice
    # can be made from the real numbers rather than from an impression.
    spellings = collections.defaultdict(collections.Counter)
    for p in products:
        for m in SIZE.finditer(p.get("name") or ""):
            u = m.group(2)
            if u.lower() in UNIT_CANON:
                spellings[UNIT_CANON[u.lower()]][u] += 1
    spellings = {k: v for k, v in spellings.items() if len(v) > 1}

    tally = collections.Counter(r["kind"] for r in rows)
    order = {k: i for i, (k, _) in enumerate(tally.most_common())}
    rows.sort(key=lambda r: (order[r["kind"]], r["name"]))

    with CSV_OUT.open("w", newline="", encoding="utf-8") as fh:
        wr = csv.writer(fh)
        wr.writerow(["problem", "name", "category", "price", "product_id"])
        for r in rows:
            wr.writerow([r["kind"], r["name"], r["category"], r["price"], r["id"]])

    _write_sheet(rows, dupes, len(products), tally, spellings)

    print(f"{len(products)} names checked, {len({r['name'] for r in rows})} have something\n")
    for k, v in tally.most_common():
        print(f"  {k:<26} {v}")
    print("\nunits spelled more than one way:")
    for canonical, forms in sorted(spellings.items()):
        shown = ", ".join(f"{f} x{n}" for f, n in forms.most_common())
        print(f"  {canonical:<4} {shown}")
    print(f"\n{CSV_OUT}   {HTML_OUT}")


def _write_sheet(rows: list, dupes: dict, total: int, tally, spellings: dict) -> None:
    sections = []

    if dupes:
        blocks = []
        for key, members in sorted(dupes.items(), key=lambda kv: -len(kv[1]))[:80]:
            lis = "".join(
                f"<li>{html.escape(m.get('name',''))} "
                f"<span class='muted'>· {html.escape(m.get('category',''))} · ₹{m.get('price','')}</span></li>"
                for m in members)
            blocks.append(f"<div class='dupe'><ul>{lis}</ul></div>")
        sections.append(f"""<section><h2>Same product, entered more than once ({len(dupes)} groups)</h2>
<p class="note">These names mean the same thing once spelling, spacing and unit are normalised. Two
records for one product split its stock, so both can read "in stock" when the shelf is empty, and a
search will only surface one of them. Worth merging.</p>
<div class="dupes">{''.join(blocks)}</div></section>""")

    if spellings:
        rowsx = "".join(
            f"<tr><td><b>{html.escape(c)}</b></td><td>" +
            ", ".join(f"{html.escape(f)} <span class='muted'>x{n}</span>" for f, n in forms.most_common()) +
            "</td></tr>"
            for c, forms in sorted(spellings.items()))
        sections.append(f"""<section><h2>Units spelled more than one way</h2>
<p class="note">Not mistakes — each of these is a reasonable way to write the unit. But the catalogue
uses several at once, which is what makes it read as unmaintained, and it means a customer searching
"500g" and one searching "500 G" are running different searches. One decision, applied everywhere.</p>
<table class="units">{rowsx}</table></section>""")

    by_kind = collections.defaultdict(list)
    for r in rows:
        if r["kind"] != "duplicate product":
            by_kind[r["kind"]].append(r)

    for kind, items in sorted(by_kind.items(), key=lambda kv: -len(kv[1])):
        names = "".join(f"<li>{html.escape(i['name'])}</li>" for i in items[:60])
        more = f"<li class='muted'>… and {len(items)-60} more, see the CSV</li>" if len(items) > 60 else ""
        sections.append(f"<section><h2>{html.escape(kind)} <span class='count'>{len(items)}</span></h2>"
                        f"<ul class='names'>{names}{more}</ul></section>")

    HTML_OUT.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Product name issues</title>
<style>
 body{{font:14px/1.5 system-ui;margin:24px;background:#fafafa;color:#222}}
 h1{{font-size:20px;margin-bottom:2px}} .sub{{color:#666;margin-bottom:20px}}
 section{{background:#fff;border:1px solid #ddd;border-radius:8px;padding:16px 18px;margin-bottom:14px}}
 h2{{font-size:15px;margin:0 0 8px}} .count{{color:#888;font-weight:400}}
 .note{{color:#666;font-size:13px;max-width:75ch;margin:0 0 12px}}
 ul.names{{columns:3;column-gap:24px;margin:0;padding-left:18px;font-size:13px}}
 ul.names li{{break-inside:avoid}}
 .dupes{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:10px}}
 .dupe{{background:#fff8e1;border:1px solid #ffe082;border-radius:6px;padding:8px 10px}}
 .dupe ul{{margin:0;padding-left:16px;font-size:13px}}
 .muted{{color:#999}}
 @media (max-width:900px){{ul.names{{columns:1}}}}
</style>
<h1>Product name issues</h1>
<div class="sub">{total} products checked · {sum(tally.values())} findings · nothing was renamed</div>
{''.join(sections)}""", encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
