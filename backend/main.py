import logging
import re
import traceback
from pathlib import Path
from datetime import datetime, timedelta
from fastapi import FastAPI, Query, HTTPException, Request, Body, Depends, File, UploadFile, Form
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from bson import ObjectId
from database import (
    products_collection, banners_collection, orders_collection,
    addresses_collection, wishlists_collection, users_collection,
    ensure_indexes,
)
from auth import generate_otp, verify_otp, create_token, get_current_user
from config import settings

log = logging.getLogger(__name__)
limiter = Limiter(key_func=get_remote_address)

_PHONE_RE = re.compile(r"^\+?91?\d{10}$")
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


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "Too many requests. Please try again later."})


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(status_code=422, content={"detail": "Invalid request data", "errors": exc.errors()})


@app.exception_handler(Exception)
async def global_error_handler(request: Request, exc: Exception):
    log.error("Unhandled error on %s %s: %s", request.method, request.url.path, traceback.format_exc())
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})

app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
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
async def firebase_login(request: Request, phone: str = Body(..., embed=True)):
    phone = (phone or "").strip()
    if not _PHONE_RE.match(phone.replace(" ", "")):
        raise HTTPException(status_code=400, detail="Invalid phone number format")

    user = await users_collection.find_one({"phone": phone})
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
    image = product.get("image_url") or product.get("image") or ""
    if image and not image.startswith("http"):
        url = f"{base_url}/static/images/{image}"
        image = url.replace("http://", "https://", 1) if "railway.app" in url else url
    product["image"] = image
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
    regex = {"$regex": q, "$options": "i"}
    pipeline = [
        {"$match": {"$or": [{"name": regex}, {"brand": regex}, {"category": regex}]}},
        {"$limit": 50},
        {"$group": {
            "_id": None,
            "names": {"$addToSet": "$name"},
            "brands": {"$addToSet": "$brand"},
            "categories": {"$addToSet": "$category"},
        }},
    ]
    results = {"names": [], "brands": [], "categories": []}
    async for doc in products_collection.aggregate(pipeline):
        q_lower = q.lower()
        results["names"] = sorted(
            [n for n in doc.get("names", []) if q_lower in n.lower()]
        )[:5]
        results["brands"] = sorted(
            {b for b in doc.get("brands", []) if b and q_lower in b.lower()}
        )[:3]
        results["categories"] = sorted(
            {c for c in doc.get("categories", []) if c and q_lower in c.lower()}
        )[:3]
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
    query = {"$or": [
        {"name": {"$regex": q, "$options": "i"}},
        {"brand": {"$regex": q, "$options": "i"}},
        {"category": {"$regex": q, "$options": "i"}},
    ]}
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


# ─── Banners ──────────────────────────────────────────────

@app.get("/banners")
async def get_banners(request: Request):
    base_url = str(request.base_url).rstrip("/")
    cursor = banners_collection.find({"active": True}).sort("order", 1)
    banners = []
    async for b in cursor:
        b = serialize_doc(b)
        img = b.get("image", "")
        if img and not img.startswith("http"):
            b["image"] = f"{base_url}/static/images/{img}"
        banners.append(b)
    return {"banners": banners}


# ─── Wishlist ─────────────────────────────────────────────

@app.get("/wishlist/{user_id}")
async def get_wishlist(user_id: str, request: Request):
    base_url = str(request.base_url).rstrip("/")
    doc = await wishlists_collection.find_one({"user_id": user_id})
    if not doc or not doc.get("product_ids"):
        return {"products": []}
    oids = [ObjectId(pid) for pid in doc["product_ids"] if ObjectId.is_valid(pid)]
    cursor = products_collection.find({"_id": {"$in": oids}})
    products = [serialize_product(p, base_url) async for p in cursor]
    return {"products": products}


@app.post("/wishlist/{user_id}/add")
async def add_to_wishlist(user_id: str, product_id: str = Body(..., embed=True)):
    await wishlists_collection.update_one(
        {"user_id": user_id},
        {"$addToSet": {"product_ids": product_id}},
        upsert=True,
    )
    return {"status": "added"}


@app.post("/wishlist/{user_id}/remove")
async def remove_from_wishlist(user_id: str, product_id: str = Body(..., embed=True)):
    await wishlists_collection.update_one(
        {"user_id": user_id},
        {"$pull": {"product_ids": product_id}},
    )
    return {"status": "removed"}


# ─── Addresses ────────────────────────────────────────────

@app.get("/addresses/{user_id}")
async def get_addresses(user_id: str):
    cursor = addresses_collection.find({"user_id": user_id})
    addresses = [serialize_doc(a) async for a in cursor]
    return {"addresses": addresses}


@app.post("/addresses/{user_id}")
async def add_address(user_id: str, address: dict = Body(...)):
    address["user_id"] = user_id
    address["created_at"] = datetime.utcnow().isoformat()
    result = await addresses_collection.insert_one(address)
    return {"id": str(result.inserted_id), "status": "created"}


@app.put("/addresses/{address_id}")
async def update_address(address_id: str, address: dict = Body(...)):
    if not ObjectId.is_valid(address_id):
        raise HTTPException(status_code=400, detail="Invalid address ID")
    address.pop("_id", None)
    address.pop("id", None)
    await addresses_collection.update_one(
        {"_id": ObjectId(address_id)},
        {"$set": address},
    )
    return {"status": "updated"}


@app.delete("/addresses/{address_id}")
async def delete_address(address_id: str):
    if not ObjectId.is_valid(address_id):
        raise HTTPException(status_code=400, detail="Invalid address ID")
    await addresses_collection.delete_one({"_id": ObjectId(address_id)})
    return {"status": "deleted"}


# ─── Orders / Checkout ────────────────────────────────────

@app.post("/orders")
async def create_order(order: dict = Body(...)):
    import random, string
    order_number = "DH" + "".join(random.choices(string.digits, k=8))
    order["order_number"] = order_number
    order["status"] = "confirmed"
    order["created_at"] = datetime.utcnow().isoformat()
    order["updated_at"] = order["created_at"]
    order["timeline"] = [
        {"status": "confirmed", "time": order["created_at"], "message": "Order confirmed"},
    ]
    result = await orders_collection.insert_one(order)
    return {
        "id": str(result.inserted_id),
        "order_number": order_number,
        "status": "confirmed",
        "estimated_delivery": order.get("delivery_slot", ""),
    }


@app.get("/orders/{user_id}")
async def get_orders(user_id: str):
    cursor = orders_collection.find(
        {"$or": [{"user_id": user_id}, {"customer_id": user_id}]}
    ).sort("created_at", -1)
    orders = [serialize_doc(o) async for o in cursor]
    return {"orders": orders}


@app.get("/orders/detail/{order_id}")
async def get_order_detail(order_id: str):
    if not ObjectId.is_valid(order_id):
        raise HTTPException(status_code=400, detail="Invalid order ID")
    order = await orders_collection.find_one({"_id": ObjectId(order_id)})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return serialize_doc(order)


# ─── Admin Dashboard ──────────────────────────────────────

@app.get("/admin/stats")
async def admin_stats():
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


@app.post("/admin/products")
async def create_product(request: Request, product: _ProductCreate):
    data = product.model_dump(exclude_none=True)
    data["created_at"] = datetime.utcnow().isoformat()
    result = await products_collection.insert_one(data)
    return {"id": str(result.inserted_id), "status": "created"}


@app.put("/admin/products/{product_id}")
async def update_product(product_id: str, product: _ProductUpdate):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    data = product.model_dump(exclude_none=True)
    data["updated_at"] = datetime.utcnow().isoformat()
    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": data})
    return {"status": "updated"}


@app.delete("/admin/products/{product_id}")
async def delete_product(product_id: str):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    await products_collection.delete_one({"_id": ObjectId(product_id)})
    return {"status": "deleted"}


@app.put("/admin/products/{product_id}/featured")
async def toggle_featured(product_id: str, featured: bool = Body(..., embed=True)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": {"featured": featured}})
    return {"status": "updated", "featured": featured}


@app.post("/admin/products/{product_id}/image")
async def upload_product_image(product_id: str, request: Request, file: UploadFile = File(...)):
    import re
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    ext = Path(file.filename or "img.jpg").suffix or ".jpg"
    slug = re.sub(r"[^a-z0-9]+", "-", product.get("name", "product").lower()).strip("-")
    filename = f"{slug}{ext}"
    filepath = STATIC_DIR / "images" / filename
    content = await file.read()
    filepath.write_bytes(content)

    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": {"image_url": filename}})
    base_url = str(request.base_url).rstrip("/")
    return {"status": "uploaded", "image_url": f"{base_url}/static/images/{filename}"}


# ─── Admin: Categories ───────────────────────────────────

@app.post("/admin/categories")
async def add_category(name: str = Body(..., embed=True)):
    existing = await products_collection.distinct("category")
    if name in existing:
        raise HTTPException(status_code=400, detail="Category already exists")
    await products_collection.insert_one({"name": f"__category_placeholder_{name}", "category": name, "price": 0, "stock": 0})
    return {"status": "created", "category": name}


@app.delete("/admin/categories/{category_name}")
async def delete_category(category_name: str):
    count = await products_collection.count_documents({"category": category_name})
    if count > 1:
        raise HTTPException(status_code=400, detail=f"Category has {count} products. Remove products first.")
    await products_collection.delete_many({"name": {"$regex": "^__category_placeholder_"},"category": category_name})
    return {"status": "deleted"}


# ─── Admin: Orders ────────────────────────────────────────

@app.get("/admin/orders")
async def admin_orders(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str | None = None,
):
    skip = (page - 1) * limit
    query = {"status": status} if status else {}
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    orders = [serialize_doc(o) async for o in cursor]
    return {"orders": orders, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@app.put("/admin/orders/{order_id}/status")
async def update_order_status(order_id: str, status: str = Body(..., embed=True)):
    if not ObjectId.is_valid(order_id):
        raise HTTPException(status_code=400, detail="Invalid order ID")
    now = datetime.utcnow().isoformat()
    await orders_collection.update_one(
        {"_id": ObjectId(order_id)},
        {
            "$set": {"status": status, "updated_at": now},
            "$push": {"timeline": {"status": status, "time": now, "message": f"Order {status}"}},
        },
    )
    return {"status": status}


# ─── Admin: Users ─────────────────────────────────────────

@app.get("/admin/users")
async def admin_users(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
):
    skip = (page - 1) * limit
    total = await users_collection.count_documents({})
    cursor = users_collection.find().sort("created_at", -1).skip(skip).limit(limit)
    users = [serialize_doc(u) async for u in cursor]
    return {"users": users, "total": total, "page": page, "pages": (total + limit - 1) // limit}


# ─── Admin: Banners ───────────────────────────────────────

@app.post("/admin/banners")
async def create_banner(banner: dict = Body(...)):
    banner["active"] = banner.get("active", True)
    banner["order"] = banner.get("order", 0)
    result = await banners_collection.insert_one(banner)
    return {"id": str(result.inserted_id), "status": "created"}


@app.delete("/admin/banners/{banner_id}")
async def delete_banner(banner_id: str):
    if not ObjectId.is_valid(banner_id):
        raise HTTPException(status_code=400, detail="Invalid banner ID")
    await banners_collection.delete_one({"_id": ObjectId(banner_id)})
    return {"status": "deleted"}
