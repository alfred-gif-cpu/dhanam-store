import logging
import re
import traceback
from pathlib import Path
from datetime import datetime, timedelta
from fastapi import FastAPI, Query, HTTPException, Request, Response, Body, Depends, File, UploadFile, Form
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from bson import ObjectId
from database import (
    products_collection, banners_collection, orders_collection,
    addresses_collection, wishlists_collection, users_collection,
    otp_collection, search_misses_collection, ensure_indexes,
)
from auth import generate_otp, verify_otp, create_token, get_current_user, verify_firebase_phone_token
from admin_auth import get_current_admin
from storage import UPLOAD_DIR, UPLOAD_PREFIX, resolve_image_url
from search_utils import (
    build_query as build_search_query,
    tokenize as search_tokens,
    normalize as normalize_search,
    build_search_text,
)
from config import settings

log = logging.getLogger(__name__)


# Error tracking: activates only when SENTRY_DSN is configured, so local dev
# and any deploy without it run unchanged.
if settings.sentry_dsn:
    try:
        import sentry_sdk
        sentry_sdk.init(
            dsn=settings.sentry_dsn,
            traces_sample_rate=0.1,
            # Order payloads and auth bodies carry customer phone numbers and
            # addresses — never ship request bodies or headers to Sentry.
            send_default_pii=False,
            max_request_body_size="never",
        )
        log.info("Sentry error tracking enabled")
    except Exception as e:
        log.warning("Sentry init failed, continuing without it: %s", e)


def _client_ip(request: Request) -> str:
    """Resolve the real client IP behind Railway's proxy.
    Railway sets X-Forwarded-For; the first entry is the originating client.
    Falls back to the direct peer address for local/non-proxied requests."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return get_remote_address(request)


limiter = Limiter(key_func=_client_ip)

_PHONE_RE = re.compile(r"^\+?91?\d{10}$")

def _escape_regex(s: str) -> str:
    return re.escape(s)
from routes_customer import router as customer_router
from routes_orders import router as orders_router
from routes_admin import router as admin_router
from routes_addresses import router as addresses_router
from routes_cart import router as cart_router
from routes_notifications import router as notifications_router
from routes_reviews import router as reviews_router

STATIC_DIR = Path(__file__).parent / "static"
STATIC_DIR.mkdir(exist_ok=True)
(STATIC_DIR / "images").mkdir(exist_ok=True)

app = FastAPI(
    title="Dhanam Store API",
    description="Backend API for Dhanam Store grocery app",
    version="2.0.0",
)
app.state.limiter = limiter

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


_CACHEABLE_IMAGE_EXTS = {"jpg", "jpeg", "png", "webp", "gif", "svg"}


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

    # Without Cache-Control the client revalidates every image on every screen.
    # The 304 is small but the round trip is not — it costs a full RTT, which
    # for customers in Hosur is most of the perceived load time.
    path = request.url.path
    if path.startswith("/static/"):
        if path.startswith(f"/static/{UPLOAD_PREFIX}/"):
            # An admin re-uploading a product photo reuses the same filename,
            # so these must go stale quickly or the new photo never appears.
            response.headers["Cache-Control"] = "public, max-age=300"
        elif path.rsplit(".", 1)[-1].lower() in _CACHEABLE_IMAGE_EXTS:
            # Catalog images ship with the build and only change on deploy.
            response.headers["Cache-Control"] = "public, max-age=604800"
        else:
            response.headers["Cache-Control"] = "public, max-age=300"
    return response


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "Too many requests. Please try again later."})


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(status_code=422, content={"detail": "Invalid request data", "errors": exc.errors()})


@app.exception_handler(Exception)
async def global_error_handler(request: Request, exc: Exception):
    log.error("Unhandled error on %s %s: %s", request.method, request.url.path, traceback.format_exc())
    # This catch-all swallows the exception before it reaches Sentry's ASGI
    # layer, so report it explicitly.
    if settings.sentry_dsn:
        try:
            import sentry_sdk
            sentry_sdk.capture_exception(exc)
        except Exception:
            pass
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})

# Mounted before /static so it wins for /static/uploads/* — UPLOAD_DIR is a
# mounted volume in production and may live outside STATIC_DIR entirely.
app.mount(f"/static/{UPLOAD_PREFIX}", StaticFiles(directory=str(UPLOAD_DIR)), name="uploads")
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/panel", include_in_schema=False)
@app.get("/panel/", include_in_schema=False)
async def admin_panel():
    """Serve the standalone web admin panel (talks to /admin/* APIs)."""
    return FileResponse(str(STATIC_DIR / "panel" / "index.html"))


app.include_router(customer_router, tags=["Customers"])
app.include_router(orders_router, tags=["Orders V2"])
app.include_router(admin_router)
app.include_router(addresses_router)
app.include_router(cart_router)
app.include_router(notifications_router)
app.include_router(reviews_router)


@app.on_event("startup")
async def startup():
    await ensure_indexes()


@app.get("/health")
async def health_check():
    """Lightweight liveness/readiness probe for Railway.
    Pings MongoDB so a hung DB connection surfaces as unhealthy."""
    try:
        await users_collection.database.command("ping")
        return {"status": "healthy"}
    except Exception:
        return JSONResponse(status_code=503, content={"status": "unhealthy"})


# ─── Auth ─────────────────────────────────────────────────

@app.post("/auth/send-otp")
@limiter.limit("5/minute")
async def send_otp(request: Request, phone: str = Body(..., embed=True)):
    phone = (phone or "").strip()
    if not _PHONE_RE.match(phone.replace(" ", "")):
        raise HTTPException(status_code=400, detail="Invalid phone number format")
    otp = await generate_otp(phone)
    response = {"status": "sent", "message": "OTP sent successfully"}
    if settings.debug:
        response["otp"] = otp
    return response


@app.post("/auth/verify-otp")
@limiter.limit("10/minute")
async def verify_otp_endpoint(request: Request, phone: str = Body(...), otp: str = Body(...)):
    phone = (phone or "").strip()
    otp = (otp or "").strip()
    if not _PHONE_RE.match(phone.replace(" ", "")):
        raise HTTPException(status_code=400, detail="Invalid phone number format")
    if not re.match(r"^\d{4}$", otp):
        raise HTTPException(status_code=400, detail="OTP must be 4 digits")
    if not await verify_otp(phone, otp):
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    user = await users_collection.find_one({"phone": phone})
    if user and user.get("is_active") is False:
        raise HTTPException(status_code=403, detail="Your account has been blocked. Please contact the store.")
    is_new = user is None
    if is_new:
        result = await users_collection.insert_one({
            "phone": phone,
            "name": "",
            "email": "",
            "created_at": datetime.utcnow().isoformat(),
        })
        user_id = str(result.inserted_id)
    else:
        user_id = str(user["_id"])

    token = create_token(user_id, phone)
    return {"token": token, "user_id": user_id, "is_new_user": is_new}


@app.post("/auth/firebase-login")
@limiter.limit("10/minute")
async def firebase_login(request: Request, id_token: str = Body(..., embed=True)):
    phone = verify_firebase_phone_token(id_token)

    user = await users_collection.find_one({"phone": phone})
    if user and user.get("is_active") is False:
        raise HTTPException(status_code=403, detail="Your account has been blocked. Please contact the store.")
    is_new = user is None
    if is_new:
        result = await users_collection.insert_one({
            "phone": phone,
            "name": "",
            "email": "",
            "created_at": datetime.utcnow().isoformat(),
        })
        user_id = str(result.inserted_id)
    else:
        user_id = str(user["_id"])

    token = create_token(user_id, phone)
    return {"token": token, "user_id": user_id, "is_new_user": is_new}


@app.get("/auth/me")
async def get_me(user: dict = Depends(get_current_user)):
    return {
        "id": user["id"],
        "phone": user.get("phone", ""),
        "name": user.get("name", ""),
        "email": user.get("email", ""),
    }


@app.delete("/auth/account")
async def delete_account(user: dict = Depends(get_current_user)):
    """Permanently delete the authenticated user and all associated data.
    Required by Google Play's account-deletion policy."""
    user_id = user["id"]
    phone = user.get("phone", "")

    await orders_collection.delete_many({"$or": [{"user_id": user_id}, {"customer_id": user_id}]})
    await addresses_collection.delete_many({"user_id": user_id})
    await wishlists_collection.delete_many({"user_id": user_id})
    await users_collection.delete_one({"_id": ObjectId(user_id)})
    if phone:
        await otp_collection.delete_many({"phone": phone})

    return {"status": "deleted", "message": "Account and all data permanently deleted"}


@app.put("/auth/profile")
async def update_profile(
    name: str = Body(""),
    email: str = Body(""),
    user: dict = Depends(get_current_user),
):
    update = {}
    if name:
        update["name"] = name
    if email:
        update["email"] = email
    if update:
        await users_collection.update_one({"phone": user["phone"]}, {"$set": update})
    return {"status": "updated"}


# ─── Recent searches (per-user, stored in the user's record) ──

_MAX_RECENT_SEARCHES = 10


@app.get("/auth/recent-searches")
async def get_recent_searches(user: dict = Depends(get_current_user)):
    return {"searches": user.get("recent_searches", [])}


@app.post("/auth/recent-searches")
async def add_recent_search(query: str = Body(..., embed=True), user: dict = Depends(get_current_user)):
    q = (query or "").strip()
    searches = list(user.get("recent_searches", []))
    if q:
        searches = [s for s in searches if s.lower() != q.lower()]
        searches.insert(0, q)
        searches = searches[:_MAX_RECENT_SEARCHES]
        await users_collection.update_one({"phone": user["phone"]}, {"$set": {"recent_searches": searches}})
    return {"searches": searches}


@app.post("/auth/recent-searches/remove")
async def remove_recent_search(query: str = Body(..., embed=True), user: dict = Depends(get_current_user)):
    q = (query or "").strip()
    searches = [s for s in user.get("recent_searches", []) if s.lower() != q.lower()]
    await users_collection.update_one({"phone": user["phone"]}, {"$set": {"recent_searches": searches}})
    return {"searches": searches}


@app.delete("/auth/recent-searches")
async def clear_recent_searches(user: dict = Depends(get_current_user)):
    await users_collection.update_one({"phone": user["phone"]}, {"$set": {"recent_searches": []}})
    return {"searches": []}


# ─── Helpers ──────────────────────────────────────────────

def serialize_doc(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


def serialize_product(product: dict, base_url: str = "") -> dict:
    product["id"] = str(product.pop("_id"))
    product["image"] = resolve_image_url(
        product.get("image_url") or product.get("image") or "", base_url
    )
    return product


# ─── Products ─────────────────────────────────────────────

@app.get("/products")
async def get_products(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    category: str | None = None,
):
    base_url = str(request.base_url).rstrip("/")
    skip = (page - 1) * limit
    query = {"category": category} if category else {}
    total = await products_collection.count_documents(query)
    cursor = products_collection.find(query).skip(skip).limit(limit)
    products = [serialize_product(p, base_url) async for p in cursor]
    return {
        "products": products,
        "total": total,
        "page": page,
        "limit": limit,
        "pages": (total + limit - 1) // limit,
    }


@app.get("/products/featured")
async def get_featured_products(request: Request, limit: int = Query(10, ge=1, le=50)):
    base_url = str(request.base_url).rstrip("/")
    cursor = products_collection.find({"featured": True}).limit(limit)
    products = [serialize_product(p, base_url) async for p in cursor]
    if not products:
        cursor = products_collection.find().limit(limit)
        products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.get("/products/flash-deals")
async def get_flash_deals(request: Request, limit: int = Query(10, ge=1, le=50)):
    base_url = str(request.base_url).rstrip("/")
    cursor = products_collection.find(
        {"$expr": {"$gt": [{"$ifNull": ["$original_price", 0]}, "$price"]}}
    ).sort("original_price", -1).limit(limit)
    products = [serialize_product(p, base_url) async for p in cursor]
    if not products:
        cursor = products_collection.find().sort("price", 1).limit(limit)
        products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.get("/products/trending")
async def get_trending(request: Request, limit: int = Query(10, ge=1, le=50)):
    import random
    base_url = str(request.base_url).rstrip("/")
    total = await products_collection.count_documents({})
    skip = random.randint(0, max(0, total - limit))
    cursor = products_collection.find().skip(skip).limit(limit)
    products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.get("/products/by-ids")
async def get_products_by_ids(request: Request, ids: str = Query(...)):
    base_url = str(request.base_url).rstrip("/")
    oid_list = [ObjectId(i) for i in ids.split(",") if ObjectId.is_valid(i)]
    if not oid_list:
        return {"products": []}
    cursor = products_collection.find({"_id": {"$in": oid_list}})
    products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.get("/products/bestsellers")
async def get_bestsellers(request: Request, limit: int = Query(10, ge=1, le=50)):
    base_url = str(request.base_url).rstrip("/")
    cursor = products_collection.find().sort("sold_count", -1).limit(limit)
    products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.get("/products/{product_id}")
async def get_product(product_id: str, request: Request):
    base_url = str(request.base_url).rstrip("/")
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return serialize_product(product, base_url)


# ─── Image credits ────────────────────────────────────────

# Photographs imported from open databases are licensed on the condition that
# the source is credited wherever the image appears, so the app carries a
# Credits screen and this is what fills it.
#
# The import scripts record the credit on each product as one string, in one
# of two shapes:
#
#     Open Food Facts (8901719100956), CC-BY-SA
#     Openverse / Jane Doe (cc-by)
#
# Parse both back into parts, so the screen can group by source and link each
# photograph to the record it came from.

_SOURCE_HOMES = {
    "open food facts": "https://world.openfoodfacts.org",
    "openverse": "https://openverse.org",
}
_CREDIT_RE = re.compile(
    r"^\s*(?P<source>[^(/]+?)\s*"
    r"(?:/\s*(?P<creator>[^(]+?)\s*)?"
    r"(?:\((?P<ref>[^)]*)\))?"
    r"(?:\s*,\s*(?P<licence>.+?))?\s*$"
)


def _parse_credit(credit: str) -> dict:
    m = _CREDIT_RE.match(credit or "")
    if not m:
        return {"source": (credit or "").strip(), "creator": "", "licence": "", "home": "", "url": ""}

    source = (m.group("source") or "").strip()
    creator = (m.group("creator") or "").strip()
    ref = (m.group("ref") or "").strip()
    licence = (m.group("licence") or "").strip()

    # The bracketed part is a barcode for Open Food Facts but the licence for
    # Openverse. Tell them apart by what they contain rather than by position.
    if ref and not licence and not ref.isdigit():
        licence, ref = ref, ""

    home = _SOURCE_HOMES.get(source.lower(), "")
    url = f"{home}/product/{ref}" if ref.isdigit() and "openfoodfacts" in home else home
    return {"source": source, "creator": creator, "licence": licence, "home": home, "url": url}


@app.get("/image-credits")
async def get_image_credits(response: Response):
    """Attribution for catalogue photographs taken from open databases."""
    groups: dict[str, dict] = {}
    cursor = products_collection.find(
        {"image_credit": {"$nin": ["", None]}},
        {"name": 1, "image_credit": 1},
    ).sort("name", 1)
    async for p in cursor:
        c = _parse_credit(p.get("image_credit", ""))
        if not c["source"]:
            continue
        group = groups.setdefault(c["source"], {
            "name": c["source"], "url": c["home"], "licences": [], "items": [],
        })
        if c["licence"] and c["licence"] not in group["licences"]:
            group["licences"].append(c["licence"])
        group["items"].append({
            "product": p.get("name", ""),
            "creator": c["creator"],
            "licence": c["licence"],
            "url": c["url"],
        })

    sources = sorted(groups.values(), key=lambda g: -len(g["items"]))
    for group in sources:
        group["count"] = len(group["items"])

    # Only changes when new photographs are imported, which is a deploy.
    response.headers["Cache-Control"] = "public, max-age=3600"
    return {"sources": sources, "total": sum(g["count"] for g in sources)}


@app.get("/categories")
async def get_categories(request: Request):
    import re
    base_url = str(request.base_url).rstrip("/")
    categories = await products_collection.distinct("category")
    result = []
    cat_dir = STATIC_DIR / "images" / "categories"
    for cat in sorted(categories):
        s = re.sub(r"[^a-z0-9]+", "-", cat.lower()).strip("-")
        img = f"{s}.svg"
        for ext in (".jpg", ".jpeg", ".png", ".webp"):
            if (cat_dir / f"{s}{ext}").exists():
                img = f"{s}{ext}"
                break
        result.append({"name": cat, "image": f"{base_url}/static/images/categories/{img}"})
    return {"categories": result}


@app.get("/search/suggestions")
async def search_suggestions(q: str = Query(..., min_length=1)):
    pipeline = [
        {"$match": build_search_query(q)},
        {"$limit": 50},
        {"$group": {
            "_id": None,
            "names": {"$addToSet": "$name"},
            "brands": {"$addToSet": "$brand"},
            "categories": {"$addToSet": "$category"},
        }},
    ]
    # Filter the grouped values the same normalized way, so a suggestion list
    # never contradicts what the full search would return.
    tokens = search_tokens(q)
    def hits(value: str) -> bool:
        n = normalize_search(value)
        return bool(n) and all(t in n for t in tokens)

    results = {"names": [], "brands": [], "categories": []}
    async for doc in products_collection.aggregate(pipeline):
        results["names"] = sorted(n for n in doc.get("names", []) if hits(n))[:5]
        results["brands"] = sorted({b for b in doc.get("brands", []) if b and hits(b)})[:3]
        results["categories"] = sorted({c for c in doc.get("categories", []) if c and hits(c)})[:3]
    return results


@app.get("/search")
async def search_products(
    request: Request,
    q: str = Query(..., min_length=1),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
):
    base_url = str(request.base_url).rstrip("/")
    skip = (page - 1) * limit
    query = build_search_query(q)
    total = await products_collection.count_documents(query)
    cursor = products_collection.find(query).skip(skip).limit(limit)
    products = [serialize_product(p, base_url) async for p in cursor]

    # A search that finds nothing is the clearest signal the catalogue has a
    # gap — either a product worth stocking, or one named differently from
    # what customers call it. Only the term is recorded, never who typed it.
    if total == 0 and page == 1:
        term = q.strip()[:80]
        if term:
            await search_misses_collection.update_one(
                {"_id": term.lower()},
                {"$inc": {"count": 1},
                 "$set": {"term": term, "last_seen": datetime.utcnow().isoformat()}},
                upsert=True,
            )
    return {
        "products": products,
        "total": total,
        "page": page,
        "limit": limit,
        "pages": (total + limit - 1) // limit,
    }


# ─── Banners ──────────────────────────────────────────────

@app.get("/banners")
async def get_banners(request: Request):
    base_url = str(request.base_url).rstrip("/")
    cursor = banners_collection.find({"active": True}).sort("order", 1)
    banners = []
    async for b in cursor:
        b = serialize_doc(b)
        b["image"] = resolve_image_url(b.get("image", ""), base_url)
        banners.append(b)
    return {"banners": banners}


# ─── Wishlist ─────────────────────────────────────────────

@app.get("/wishlist/{user_id}")
async def get_wishlist(user_id: str, request: Request, user: dict = Depends(get_current_user)):
    if user["id"] != user_id:
        raise HTTPException(status_code=403, detail="Access denied")
    base_url = str(request.base_url).rstrip("/")
    doc = await wishlists_collection.find_one({"user_id": user_id})
    if not doc or not doc.get("product_ids"):
        return {"products": []}
    oids = [ObjectId(pid) for pid in doc["product_ids"] if ObjectId.is_valid(pid)]
    cursor = products_collection.find({"_id": {"$in": oids}})
    products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.post("/wishlist/{user_id}/add")
async def add_to_wishlist(user_id: str, product_id: str = Body(..., embed=True), user: dict = Depends(get_current_user)):
    if user["id"] != user_id:
        raise HTTPException(status_code=403, detail="Access denied")
    await wishlists_collection.update_one(
        {"user_id": user_id},
        {"$addToSet": {"product_ids": product_id}},
        upsert=True,
    )
    return {"status": "added"}


@app.post("/wishlist/{user_id}/remove")
async def remove_from_wishlist(user_id: str, product_id: str = Body(..., embed=True), user: dict = Depends(get_current_user)):
    if user["id"] != user_id:
        raise HTTPException(status_code=403, detail="Access denied")
    await wishlists_collection.update_one(
        {"user_id": user_id},
        {"$pull": {"product_ids": product_id}},
    )
    return {"status": "removed"}


# ─── Addresses ────────────────────────────────────────────

@app.get("/addresses/{user_id}")
async def get_addresses(user_id: str, user: dict = Depends(get_current_user)):
    if user["id"] != user_id:
        raise HTTPException(status_code=403, detail="Access denied")
    cursor = addresses_collection.find({"user_id": user_id})
    addresses = [serialize_doc(a) async for a in cursor]
    return {"addresses": addresses}


@app.post("/addresses/{user_id}")
async def add_address(user_id: str, address: dict = Body(...), user: dict = Depends(get_current_user)):
    if user["id"] != user_id:
        raise HTTPException(status_code=403, detail="Access denied")
    address["user_id"] = user_id
    address["created_at"] = datetime.utcnow().isoformat()
    result = await addresses_collection.insert_one(address)
    return {"id": str(result.inserted_id), "status": "created"}


# Addresses, admin product writes and admin order routes live in their own
# routers, which register first and therefore win. Duplicates here were dead
# code that twice hid a fix applied to the wrong copy.

@app.get("/orders/{user_id}")
async def get_orders(user_id: str, user: dict = Depends(get_current_user)):
    if user["id"] != user_id:
        raise HTTPException(status_code=403, detail="Access denied")
    cursor = orders_collection.find(
        {"$or": [{"user_id": user_id}, {"customer_id": user_id}]}
    ).sort("created_at", -1)
    orders = [serialize_doc(o) async for o in cursor]
    return {"orders": orders}


@app.get("/orders/detail/{order_id}")
async def get_order_detail(order_id: str, user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(order_id):
        raise HTTPException(status_code=400, detail="Invalid order ID")
    order = await orders_collection.find_one({"_id": ObjectId(order_id)})
    # 404 rather than 403 for someone else's order: confirming an id exists is
    # itself a disclosure, and order ids are sequential.
    if not order or user["id"] not in (order.get("user_id"), order.get("customer_id")):
        raise HTTPException(status_code=404, detail="Order not found")
    return serialize_doc(order)


# ─── Admin Dashboard ──────────────────────────────────────

@app.get("/admin/stats")
async def admin_stats(_admin: dict = Depends(get_current_admin)):
    total_products = await products_collection.count_documents({})
    total_orders = await orders_collection.count_documents({})
    total_users = await users_collection.count_documents({})

    revenue_pipeline = [{"$group": {"_id": None, "total": {"$sum": "$grand_total"}}}]
    revenue = 0.0
    async for doc in orders_collection.aggregate(revenue_pipeline):
        revenue = doc.get("total", 0)

    categories = await products_collection.distinct("category")

    status_pipeline = [{"$group": {"_id": "$status", "count": {"$sum": 1}}}]
    order_by_status = {}
    async for doc in orders_collection.aggregate(status_pipeline):
        order_by_status[doc["_id"] or "unknown"] = doc["count"]

    cat_pipeline = [{"$group": {"_id": "$category", "count": {"$sum": 1}}}]
    products_by_category = {}
    async for doc in products_collection.aggregate(cat_pipeline):
        products_by_category[doc["_id"] or "unknown"] = doc["count"]

    low_stock = await products_collection.count_documents({"stock": {"$lte": 5, "$gt": 0}})
    out_of_stock = await products_collection.count_documents({"stock": 0})

    return {
        "total_products": total_products,
        "total_orders": total_orders,
        "total_users": total_users,
        "total_revenue": revenue,
        "total_categories": len(categories),
        "low_stock": low_stock,
        "out_of_stock": out_of_stock,
        "orders_by_status": order_by_status,
        "products_by_category": products_by_category,
    }


# ─── Admin: Products ─────────────────────────────────────

from pydantic import BaseModel as _BM, Field as _F

class _ProductCreate(_BM):
    name: str = _F(min_length=1, max_length=200)
    price: float = _F(gt=0)
    category: str = _F(min_length=1)
    stock: int = _F(ge=0, default=0)
    description: str = ""
    brand: str = ""
    unit: str = ""
    original_price: float | None = None
    featured: bool = False

    class Config:
        extra = "allow"


class _ProductUpdate(_BM):
    name: str | None = None
    price: float | None = _F(default=None, gt=0)
    category: str | None = None
    stock: int | None = _F(default=None, ge=0)
    description: str | None = None
    brand: str | None = None
    unit: str | None = None
    original_price: float | None = None
    featured: bool | None = None

    class Config:
        extra = "allow"


# Addresses, admin product writes and admin order routes live in their own
# routers, which register first and therefore win. Duplicates here were dead
# code that twice hid a fix applied to the wrong copy.

@app.put("/admin/products/{product_id}/featured")
async def toggle_featured(product_id: str, featured: bool = Body(..., embed=True), _admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": {"featured": featured}})
    return {"status": "updated", "featured": featured}


# Product image upload lives in routes_admin.py — that router registers first,
# so a duplicate defined here would never receive a request.


# ─── Admin: Categories ───────────────────────────────────

@app.post("/admin/categories")
async def add_category(name: str = Body(..., embed=True), _admin: dict = Depends(get_current_admin)):
    existing = await products_collection.distinct("category")
    if name in existing:
        raise HTTPException(status_code=400, detail="Category already exists")
    await products_collection.insert_one({"name": f"__category_placeholder_{name}", "category": name, "price": 0, "stock": 0})
    return {"status": "created", "category": name}


@app.delete("/admin/categories/{category_name}")
async def delete_category(category_name: str, _admin: dict = Depends(get_current_admin)):
    count = await products_collection.count_documents({"category": category_name})
    if count > 1:
        raise HTTPException(status_code=400, detail=f"Category has {count} products. Remove products first.")
    await products_collection.delete_many({"name": {"$regex": "^__category_placeholder_"},"category": category_name})
    return {"status": "deleted"}


# ─── Admin: Orders ────────────────────────────────────────

# Addresses, admin product writes and admin order routes live in their own
# routers, which register first and therefore win. Duplicates here were dead
# code that twice hid a fix applied to the wrong copy.

@app.get("/admin/users")
async def admin_users(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    _admin: dict = Depends(get_current_admin),
):
    skip = (page - 1) * limit
    total = await users_collection.count_documents({})
    cursor = users_collection.find().sort("created_at", -1).skip(skip).limit(limit)
    users = [serialize_doc(u) async for u in cursor]
    return {"users": users, "total": total, "page": page, "pages": (total + limit - 1) // limit}


# ─── Admin: Banners ───────────────────────────────────────

@app.post("/admin/banners")
async def create_banner(banner: dict = Body(...), _admin: dict = Depends(get_current_admin)):
    banner["active"] = banner.get("active", True)
    banner["order"] = banner.get("order", 0)
    result = await banners_collection.insert_one(banner)
    return {"id": str(result.inserted_id), "status": "created"}


@app.delete("/admin/banners/{banner_id}")
async def delete_banner(banner_id: str, _admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(banner_id):
        raise HTTPException(status_code=400, detail="Invalid banner ID")
    await banners_collection.delete_one({"_id": ObjectId(banner_id)})
    return {"status": "deleted"}
