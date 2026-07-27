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


def build_search_text(product: dict) -> str:
    """Normalized haystack for a product: name + brand + category."""
    return normalize(
        " ".join(
            str(product.get(f) or "")
            for f in ("name", "brand", "category")
        )
    )


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
    for token in tokens:
        escaped = re.escape(token)
        raw = re.escape(q.strip())
        clauses.append({"$or": [
            {"search_text": {"$regex": escaped}},
            # Legacy fallback for documents not yet backfilled.
            {"search_text": {"$exists": False}, "name": {"$regex": raw, "$options": "i"}},
            {"search_text": {"$exists": False}, "brand": {"$regex": raw, "$options": "i"}},
            {"search_text": {"$exists": False}, "category": {"$regex": raw, "$options": "i"}},
        ]})

    return clauses[0] if len(clauses) == 1 else {"$and": clauses}
