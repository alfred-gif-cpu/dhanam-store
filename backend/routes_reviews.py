import re
import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, field_validator
from bson import ObjectId
from database import db
from auth import get_current_user

log = logging.getLogger(__name__)

router = APIRouter(prefix="/reviews", tags=["Reviews"])

reviews_collection = db["reviews"]
users_collection = db["users"]
orders_collection = db["orders"]

# A value that looks like a phone number must never be shown publicly.
_PHONE_RE = re.compile(r"^\+?\d[\d\s\-]{6,}$")

# Basic content-quality guards — not a substitute for moderation, but stops
# the common abuse cases: empty/one-word reviews, keyboard-mash spam, and
# a short list of slurs/profanity.
_REPEATED_CHAR_RE = re.compile(r"(.)\1{4,}")
_BANNED_WORDS = {
    "fuck", "shit", "bitch", "asshole", "bastard", "cunt", "whore", "slut",
    "randi", "chutiya", "madarchod", "behenchod", "bhosdi", "gandu",
}


async def _has_delivered_purchase(user_id: str, product_id: str) -> bool:
    """A review is only allowed for products the user has actually received."""
    order = await orders_collection.find_one({
        "$or": [{"customer_id": user_id}, {"user_id": user_id}],
        "items.product_id": product_id,
        "order_status": "Delivered",
    })
    return order is not None


def _validate_review_text(comment: str) -> str:
    text = comment.strip()
    if len(text) < 10:
        raise HTTPException(status_code=400, detail="Please write at least 10 characters describing your experience")
    if len(text) > 1000:
        raise HTTPException(status_code=400, detail="Review is too long (max 1000 characters)")
    if _REPEATED_CHAR_RE.search(text):
        raise HTTPException(status_code=400, detail="Review looks like spam. Please write a genuine review")
    words = re.findall(r"[a-zA-Z']+", text.lower())
    if any(bad in w for w in words for bad in _BANNED_WORDS):
        raise HTTPException(status_code=400, detail="Review contains inappropriate language. Please revise")
    return text


async def _account_names(reviews: list[dict]) -> dict:
    """Map user_id -> current account name for the given reviews."""
    oids = []
    for r in reviews:
        uid = r.get("user_id")
        if uid:
            try:
                oids.append(ObjectId(uid))
            except Exception as e:
                log.warning("Invalid user_id in review: %s – %s", uid, e)
    names: dict[str, str] = {}
    if oids:
        async for u in users_collection.find({"_id": {"$in": oids}}, {"name": 1}):
            names[str(u["_id"])] = (u.get("name") or "").strip()
    return names


def _display_name(account_name: str, stored_name: str) -> str:
    """Prefer the account's current name; never expose a phone number."""
    name = (account_name or "").strip() or (stored_name or "").strip()
    if not name or _PHONE_RE.match(name):
        return "Customer"
    return name


class CreateReviewRequest(BaseModel):
    product_id: str
    rating: int
    title: str = ""
    comment: str

    @field_validator("title")
    @classmethod
    def _clean_title(cls, v: str) -> str:
        return v.strip()[:100]


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


@router.post("/")
async def create_review(req: CreateReviewRequest, user: dict = Depends(get_current_user)):
    if req.rating < 1 or req.rating > 5:
        raise HTTPException(status_code=400, detail="Rating must be 1-5")

    comment = _validate_review_text(req.comment)
    user_id = user["id"]
    user_name = (user.get("name") or "").strip() or "Customer"

    if not await _has_delivered_purchase(user_id, req.product_id):
        raise HTTPException(
            status_code=403,
            detail="You can only review products from orders that have been delivered to you",
        )

    existing = await reviews_collection.find_one({
        "product_id": req.product_id,
        "user_id": user_id,
    })
    if existing:
        await reviews_collection.update_one(
            {"_id": existing["_id"]},
            {"$set": {
                "rating": req.rating,
                "title": req.title,
                "comment": comment,
                "user_name": user_name,
                "updated_at": datetime.utcnow().isoformat(),
            }},
        )
        return {"status": "updated", "id": str(existing["_id"])}

    review = {
        "product_id": req.product_id,
        "user_id": user_id,
        "user_name": user_name,
        "rating": req.rating,
        "title": req.title,
        "comment": comment,
        "helpful_count": 0,
        "created_at": datetime.utcnow().isoformat(),
        "updated_at": datetime.utcnow().isoformat(),
    }
    result = await reviews_collection.insert_one(review)
    return {"status": "created", "id": str(result.inserted_id)}


@router.get("/can-review/{product_id}")
async def can_review(product_id: str, user: dict = Depends(get_current_user)):
    eligible = await _has_delivered_purchase(user["id"], product_id)
    return {"eligible": eligible}


@router.get("/product/{product_id}")
async def get_product_reviews(product_id: str, limit: int = 20, skip: int = 0):
    reviews = await reviews_collection.find(
        {"product_id": product_id}
    ).sort("created_at", -1).skip(skip).limit(limit).to_list(limit)

    # Show the account name only; never leak a phone number (incl. older reviews).
    name_by_id = await _account_names(reviews)
    for r in reviews:
        r["user_name"] = _display_name(name_by_id.get(r.get("user_id"), ""), r.get("user_name"))

    total = await reviews_collection.count_documents({"product_id": product_id})

    pipeline = [
        {"$match": {"product_id": product_id}},
        {"$group": {
            "_id": None,
            "avg_rating": {"$avg": "$rating"},
            "count": {"$sum": 1},
            "r1": {"$sum": {"$cond": [{"$eq": ["$rating", 1]}, 1, 0]}},
            "r2": {"$sum": {"$cond": [{"$eq": ["$rating", 2]}, 1, 0]}},
            "r3": {"$sum": {"$cond": [{"$eq": ["$rating", 3]}, 1, 0]}},
            "r4": {"$sum": {"$cond": [{"$eq": ["$rating", 4]}, 1, 0]}},
            "r5": {"$sum": {"$cond": [{"$eq": ["$rating", 5]}, 1, 0]}},
        }},
    ]
    stats_cursor = await reviews_collection.aggregate(pipeline).to_list(1)
    stats = stats_cursor[0] if stats_cursor else {
        "avg_rating": 0, "count": 0,
        "r1": 0, "r2": 0, "r3": 0, "r4": 0, "r5": 0,
    }
    stats.pop("_id", None)

    return {
        "reviews": [serialize(r) for r in reviews],
        "total": total,
        "stats": stats,
    }


@router.delete("/{review_id}")
async def delete_review(review_id: str, user: dict = Depends(get_current_user)):
    review = await reviews_collection.find_one({"_id": ObjectId(review_id)})
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    if review["user_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Not your review")
    await reviews_collection.delete_one({"_id": ObjectId(review_id)})
    return {"status": "deleted"}


@router.post("/{review_id}/helpful")
async def mark_helpful(review_id: str):
    result = await reviews_collection.update_one(
        {"_id": ObjectId(review_id)},
        {"$inc": {"helpful_count": 1}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Review not found")
    return {"status": "ok"}
