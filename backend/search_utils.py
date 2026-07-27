"""Search normalization.

Customers type product names the way they say them, not the way they are
stored: "3roses" for "3 Roses 100 G (S)", "amulbutter", "maggi 2 min". A regex
against the raw name misses all of those because it is sensitive to spaces and
punctuation that the customer had no reason to reproduce.

Every product carries a `search_text` field holding its name, brand and
category stripped down to lowercase alphanumerics. Queries get the same
treatment, so spacing and punctuation drop out of the comparison entirely and
"3roses", "3 Roses" and "3-ROSES" all become the same lookup.
"""
import re

_NON_ALNUM = re.compile(r"[^a-z0-9]+")


def normalize(text: str) -> str:
    """Reduce text to lowercase alphanumerics: '3 Roses 100 G (S)' -> '3roses100gs'."""
    return _NON_ALNUM.sub("", (text or "").lower())


def tokenize(query: str) -> list[str]:
    """Split a query into normalized terms, so word order stops mattering.

    'roses tea' -> ['roses', 'tea'], each of which must appear somewhere in a
    product's search_text for it to match.
    """
    return [t for t in (_NON_ALNUM.sub("", w.lower()) for w in (query or "").split()) if t]


def _combined(product: dict) -> str:
    return " ".join(str(product.get(f) or "") for f in ("name", "brand", "category"))


def build_search_text(product: dict) -> str:
    """Normalized haystack for a product: name + brand + category, no spaces."""
    return normalize(_combined(product))


def build_search_words(product: dict) -> str:
    """Same text, but kept as space-separated words.

    Word boundaries are needed for synonym matching: expanding "colgate" to
    the catalog's "col" and matching it as a bare substring would also hit
    "broccoli". Matching \\bcol against this field will not.
    """
    return " ".join(w for w in _NON_ALNUM.sub(" ", _combined(product).lower()).split() if w)


# The catalog abbreviates brand names ("Brit 50-50", "Col Paste") but customers
# search the full name. Each entry maps what a customer types to what the
# product is actually called. Only unambiguous cases belong here — a wrong
# alias silently pollutes results, which is worse than returning nothing.
BRAND_SYNONYMS: dict[str, tuple[str, ...]] = {
    "britannia": ("brit",),
    "himalaya": ("him",),
    "gillette": ("gil",),
    "colgate": ("col",),
    "parle": ("par",),
    "sakthi": ("sak",),
    "yardley": ("yard",),
}


def build_query(q: str) -> dict:
    """Build the Mongo filter for a customer's search string.

    Every token must match, which keeps multi-word searches precise, and each
    is matched against the normalized field so spacing never matters. Falls
    back to the raw fields for any document that predates search_text, so
    search keeps working during a backfill.
    """
    tokens = tokenize(q)
    if not tokens:
        return {"_id": {"$exists": False}}  # matches nothing

    clauses = []
    raw = re.escape(q.strip())
    for token in tokens:
        alternatives = [{"search_text": {"$regex": re.escape(token)}}]

        # Synonyms match only as the first whole word. The catalog puts the
        # abbreviated brand at the start ("Col Paste"), while the same letters
        # mid-name mean something else entirely — "Hair Col" and "Water Col
        # Pen" are colour, not Colgate. Anchoring also stops "col" matching
        # "broccoli" and "par" matching "parachute".
        for alias in BRAND_SYNONYMS.get(token, ()):
            alternatives.append({"search_words": {"$regex": rf"^{re.escape(alias)}\b"}})

        # Legacy fallback for documents not yet backfilled.
        alternatives += [
            {"search_text": {"$exists": False}, "name": {"$regex": raw, "$options": "i"}},
            {"search_text": {"$exists": False}, "brand": {"$regex": raw, "$options": "i"}},
            {"search_text": {"$exists": False}, "category": {"$regex": raw, "$options": "i"}},
        ]
        clauses.append({"$or": alternatives})

    return clauses[0] if len(clauses) == 1 else {"$and": clauses}
