import re
import logging
from datetime import datetime
from pathlib import Path
from fastapi import APIRouter, Query, HTTPException, Request, Body, Depends, File, UploadFile
from bson import ObjectId

log = logging.getLogger(__name__)
from database import (
    admins_collection, audit_logs_collection, products_collection,
    orders_collection, customers_collection, users_collection,
    addresses_collection, wishlists_collection,
)
from admin_auth import (
    hash_password, verify_password, create_admin_token, get_current_admin,
)
from inventory import release_stock, should_release
from order_events import order_delivered
from push_service import notify_delivery_ready
from storage import read_image_upload, save_image, resolve_image_url, slugify
from search_utils import build_search_text, build_search_words

router = APIRouter(prefix="/admin", tags=["Admin"])


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


def _now() -> str:
    return datetime.utcnow().isoformat()


async def _log(admin_email: str, action: str, details: str = ""):
    await audit_logs_collection.insert_one({
        "admin_email": admin_email,
        "action": action,
        "details": details,
        "timestamp": _now(),
    })


# ─── Auth ─────────────────────────────────────────────────

@router.post("/login")
async def admin_login(email: str = Body(...), password: str = Body(...)):
    admin = await admins_collection.find_one({"email": email})
    if not admin:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not verify_password(password, admin["password"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_admin_token(str(admin["_id"]), email)
    must_change = admin.get("must_change_password", False)
    role = admin.get("role", "owner")

    await _log(email, "login", f"{role} logged in")
    return {
        "token": token,
        "email": email,
        "name": admin.get("name", "Admin"),
        "role": role,
        "must_change_password": must_change,
    }


@router.put("/change-password")
async def change_password(
    current_password: str = Body(...),
    new_password: str = Body(...),
    admin: dict = Depends(get_current_admin),
):
    if not verify_password(current_password, admin["password"]):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if len(new_password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    await admins_collection.update_one(
        {"email": admin["email"]},
        {"$set": {"password": hash_password(new_password), "must_change_password": False, "updated_at": _now()}},
    )
    await _log(admin["email"], "password_changed", "Admin changed password")
    return {"status": "password_changed"}


@router.get("/me")
async def admin_me(admin: dict = Depends(get_current_admin)):
    return {"id": admin["id"], "email": admin.get("email", ""), "name": admin.get("name", "Admin"), "role": admin.get("role", "owner")}


def _require_owner(admin: dict):
    if admin.get("role", "owner") != "owner":
        raise HTTPException(status_code=403, detail="Owner access required")


# ─── Staff (delivery employees) ───────────────────────────

@router.get("/staff")
async def list_staff(admin: dict = Depends(get_current_admin)):
    _require_owner(admin)
    cursor = admins_collection.find({"role": "delivery"}).sort("created_at", -1)
    staff = []
    async for s in cursor:
        staff.append({
            "id": str(s["_id"]),
            "email": s.get("email", ""),
            "name": s.get("name", ""),
            "phone": s.get("phone", ""),
            "active": s.get("active", True),
            "created_at": s.get("created_at", ""),
        })
    return {"staff": staff}


@router.post("/staff")
async def create_staff(
    name: str = Body(...),
    email: str = Body(...),
    phone: str = Body(""),
    password: str = Body(...),
    admin: dict = Depends(get_current_admin),
):
    _require_owner(admin)
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")
    existing = await admins_collection.find_one({"email": email})
    if existing:
        raise HTTPException(status_code=400, detail="An account with this email already exists")
    await admins_collection.insert_one({
        "email": email,
        "password": hash_password(password),
        "name": name,
        "phone": phone,
        "role": "delivery",
        "active": True,
        "must_change_password": False,
        "created_at": _now(),
    })
    await _log(admin["email"], "staff_created", f"Created delivery staff {email}")
    return {"status": "created"}


@router.delete("/staff/{staff_id}")
async def delete_staff(staff_id: str, admin: dict = Depends(get_current_admin)):
    _require_owner(admin)
    await admins_collection.delete_one({"_id": ObjectId(staff_id), "role": "delivery"})
    await _log(admin["email"], "staff_deleted", f"Removed staff {staff_id}")
    return {"status": "deleted"}


# ─── Dashboard ────────────────────────────────────────────

@router.get("/dashboard")
async def admin_dashboard(admin: dict = Depends(get_current_admin)):
    now = datetime.utcnow()
    today_start = datetime(now.year, now.month, now.day).isoformat()
    month_start = datetime(now.year, now.month, 1).isoformat()

    total_products = await products_collection.count_documents({})
    # Real customer accounts live in `users` (phone-OTP logins); the legacy
    # `customers` collection is empty.
    total_customers = await users_collection.count_documents({})
    total_users = total_customers
    total_orders = await orders_collection.count_documents({})

    rev_today = 0.0
    async for doc in orders_collection.aggregate([
        {"$match": {"created_at": {"$gte": today_start}}},
        {"$group": {"_id": None, "t": {"$sum": {"$ifNull": ["$total_amount", "$grand_total"]}}}},
    ]):
        rev_today = doc.get("t", 0)

    rev_month = 0.0
    async for doc in orders_collection.aggregate([
        {"$match": {"created_at": {"$gte": month_start}}},
        {"$group": {"_id": None, "t": {"$sum": {"$ifNull": ["$total_amount", "$grand_total"]}}}},
    ]):
        rev_month = doc.get("t", 0)

    low_stock = await products_collection.count_documents({"stock": {"$gt": 0, "$lt": 10}})
    out_of_stock = await products_collection.count_documents({"stock": 0})

    orders_today = await orders_collection.count_documents({"created_at": {"$gte": today_start}})

    order_status = {}
    async for doc in orders_collection.aggregate([{"$group": {"_id": "$order_status", "c": {"$sum": 1}}}]):
        order_status[doc["_id"] or "unknown"] = doc["c"]

    return {
        "total_products": total_products,
        "total_customers": total_customers,
        "total_users": total_users,
        "total_orders": total_orders,
        "orders_today": orders_today,
        "revenue_today": round(rev_today, 2),
        "revenue_this_month": round(rev_month, 2),
        "low_stock": low_stock,
        "out_of_stock": out_of_stock,
        "orders_by_status": order_status,
    }


# ─── Products ─────────────────────────────────────────────

@router.get("/products")
async def list_products(
    request: Request,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    q: str = Query(""),
    status: str = Query("", description="visible | hidden — omit for all"),
    admin: dict = Depends(get_current_admin),
):
    skip = (page - 1) * limit
    query: dict = {}
    if q:
        query["$or"] = [
            {"name": {"$regex": re.escape(q), "$options": "i"}},
            {"brand": {"$regex": re.escape(q), "$options": "i"}},
            {"category": {"$regex": re.escape(q), "$options": "i"}},
        ]
    # Absent counts as visible, matching what the shop does — otherwise the
    # filter and the customer's view would disagree about the same product.
    if status == "visible":
        query["is_active"] = {"$ne": False}
    elif status == "hidden":
        query["is_active"] = False
    total = await products_collection.count_documents(query)
    cursor = products_collection.find(query).sort("name", 1).skip(skip).limit(limit)
    products = []
    base_url = str(request.base_url).rstrip("/")
    async for p in cursor:
        p["id"] = str(p.pop("_id"))
        p["image"] = resolve_image_url(p.get("image_url") or p.get("image") or "", base_url)
        products.append(p)
    return {"products": products, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.get("/products/{product_id}")
async def get_product(product_id: str, request: Request, admin: dict = Depends(get_current_admin)):
    """One product, for the edit form.

    The panel used to find it by fetching the first hundred products and
    searching that list, so editing anything alphabetically later opened an
    empty form — and saving it would have written those blanks back.
    """
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    product["id"] = str(product.pop("_id"))
    product["image"] = resolve_image_url(
        product.get("image_url") or product.get("image") or "",
        str(request.base_url).rstrip("/"),
    )
    return product


@router.delete("/products/{product_id}/image")
async def remove_product_image(product_id: str, admin: dict = Depends(get_current_admin)):
    """Drop a product's photograph, leaving the product itself alone.

    For when the picture is wrong and no replacement is to hand: a placeholder
    is honest, a photograph of the wrong thing is not. The file is left on
    disk — it costs nothing there, and unpicking a shared filename is a worse
    risk than a few unused kilobytes.
    """
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)}, {"name": 1})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    await products_collection.update_one(
        {"_id": ObjectId(product_id)},
        {"$set": {"image_url": ""}, "$unset": {"image_credit": ""}},
    )
    await _log(admin["email"], "product_image_removed", f"Image removed: {product.get('name', product_id)}")
    return {"status": "removed"}


@router.put("/products/{product_id}/visibility")
async def set_product_visibility(
    product_id: str,
    visible: bool = Body(..., embed=True),
    admin: dict = Depends(get_current_admin),
):
    """Take a product off the shelf, or put it back.

    Hiding is not deleting: the product keeps its price, stock and photograph,
    and an order already placed for it still works. It simply stops appearing
    in the app. Seasonal lines and anything not worth a delivery run belong
    here rather than in the bin.
    """
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)}, {"name": 1})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    await products_collection.update_one(
        {"_id": ObjectId(product_id)}, {"$set": {"is_active": visible}}
    )
    await _log(admin["email"], "product_visibility",
               f"{'Shown' if visible else 'Hidden'}: {product.get('name', product_id)}")
    return {"status": "ok", "visible": visible}


@router.post("/products")
async def create_product(product: dict = Body(...), admin: dict = Depends(get_current_admin)):
    product["created_at"] = _now()
    product["search_text"] = build_search_text(product)
    product["search_words"] = build_search_words(product)
    result = await products_collection.insert_one(product)
    await _log(admin["email"], "product_added", f"Added: {product.get('name', '')}")
    return {"id": str(result.inserted_id), "status": "created"}


@router.put("/products/{product_id}")
async def update_product(product_id: str, data: dict = Body(...), admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    data.pop("_id", None)
    data.pop("id", None)
    data["updated_at"] = _now()

    # Rebuild from the merged document: an edit may touch only one of the
    # fields search_text is derived from, and a stale value makes the product
    # unfindable under its new name.
    if any(f in data for f in ("name", "brand", "category")):
        existing = await products_collection.find_one({"_id": ObjectId(product_id)}) or {}
        merged = {**existing, **data}
        data["search_text"] = build_search_text(merged)
        data["search_words"] = build_search_words(merged)

    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": data})
    await _log(admin["email"], "product_edited", f"Edited product: {product_id}")
    return {"status": "updated"}


@router.delete("/products/{product_id}")
async def delete_product(product_id: str, admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    await products_collection.delete_one({"_id": ObjectId(product_id)})
    await _log(admin["email"], "product_deleted", f"Deleted: {product.get('name', '') if product else product_id}")
    return {"status": "deleted"}


@router.post("/products/{product_id}/image")
async def upload_image(product_id: str, request: Request, file: UploadFile = File(...), admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    content, ext = await read_image_upload(file)
    filename = f"{slugify(product.get('name', ''), 'product')}{ext}"
    stored = save_image(content, filename)

    # The credit belongs to the photograph, so it leaves with it. Without this
    # a shop photo replacing an Open Food Facts one keeps that credit: the
    # Photo Credits screen would attribute your own picture to someone else,
    # and list it as CC-BY-SA, which hands your work away to anyone reading.
    await products_collection.update_one(
        {"_id": ObjectId(product_id)},
        {"$set": {"image_url": stored}, "$unset": {"image_credit": ""}},
    )
    base_url = str(request.base_url).rstrip("/")
    await _log(admin["email"], "product_image_uploaded", f"Image for product: {product_id}")
    return {"status": "uploaded", "image_url": resolve_image_url(stored, base_url)}


# ─── Inventory ────────────────────────────────────────────

@router.get("/inventory")
async def get_inventory(
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    filter: str = Query(""),
    admin: dict = Depends(get_current_admin),
):
    skip = (page - 1) * limit
    query: dict = {}
    if filter == "low":
        query["stock"] = {"$gt": 0, "$lt": 10}
    elif filter == "out":
        query["stock"] = 0
    elif filter == "in":
        query["stock"] = {"$gte": 10}

    total = await products_collection.count_documents(query)
    cursor = products_collection.find(query, {"name": 1, "category": 1, "stock": 1, "price": 1}).sort("stock", 1).skip(skip).limit(limit)
    items = []
    async for p in cursor:
        items.append({"id": str(p["_id"]), "name": p.get("name", ""), "category": p.get("category", ""),
                       "stock": p.get("stock", 0), "price": p.get("price", 0)})
    return {"items": items, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.put("/inventory/{product_id}")
async def update_stock(product_id: str, stock: int = Body(..., embed=True), admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": {"stock": stock, "updated_at": _now()}})
    await _log(admin["email"], "stock_updated", f"Product {product_id} stock set to {stock}")
    return {"status": "updated", "stock": stock}


@router.put("/inventory/{product_id}/receive")
async def receive_stock(product_id: str, quantity: int = Body(..., embed=True), admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(status_code=400, detail="Invalid product ID")
    if quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be positive")
    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$inc": {"stock": quantity}, "$set": {"updated_at": _now()}})
    await _log(admin["email"], "stock_received", f"Product {product_id} received {quantity} units")
    return {"status": "received", "quantity": quantity}


# ─── Customers ────────────────────────────────────────────

@router.get("/customers")
async def list_customers(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    q: str = Query(""),
    status: str = Query(""),
    admin: dict = Depends(get_current_admin),
):
    # Real customers are the phone-OTP accounts in `users` — the legacy
    # `customers` collection is empty and nothing writes to it.
    skip = (page - 1) * limit
    query: dict = {}
    if q:
        query["$or"] = [
            {"name": {"$regex": re.escape(q), "$options": "i"}},
            {"phone": {"$regex": re.escape(q), "$options": "i"}},
            {"email": {"$regex": re.escape(q), "$options": "i"}},
        ]
    if status == "active":
        query["is_active"] = {"$ne": False}
    elif status == "blocked":
        query["is_active"] = False

    total = await users_collection.count_documents(query)
    cursor = users_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    customers = [serialize(c) async for c in cursor]
    return {"customers": customers, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.put("/customers/{user_id}/block")
async def block_customer(user_id: str, admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=400, detail="Invalid user ID")
    await users_collection.update_one({"_id": ObjectId(user_id)}, {"$set": {"is_active": False}})
    await _log(admin["email"], "customer_blocked", f"Blocked customer: {user_id}")
    return {"status": "blocked"}


@router.put("/customers/{user_id}/unblock")
async def unblock_customer(user_id: str, admin: dict = Depends(get_current_admin)):
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=400, detail="Invalid user ID")
    await users_collection.update_one({"_id": ObjectId(user_id)}, {"$set": {"is_active": True}})
    await _log(admin["email"], "customer_unblocked", f"Unblocked customer: {user_id}")
    return {"status": "unblocked"}


@router.delete("/customers/{user_id}")
async def delete_customer(user_id: str, admin: dict = Depends(get_current_admin)):
    _require_owner(admin)
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=400, detail="Invalid user ID")
    user = await users_collection.find_one({"_id": ObjectId(user_id)})
    if not user:
        raise HTTPException(status_code=404, detail="Customer not found")
    # Refuse to delete accounts with order history — that would orphan real
    # sales records. Block such accounts instead.
    order_count = await orders_collection.count_documents({"user_id": user_id})
    if order_count > 0:
        raise HTTPException(
            status_code=400,
            detail=f"Customer has {order_count} order(s). Block the account instead of deleting it.",
        )
    await users_collection.delete_one({"_id": ObjectId(user_id)})
    await addresses_collection.delete_many({"user_id": user_id})
    await wishlists_collection.delete_many({"user_id": user_id})
    await _log(admin["email"], "customer_deleted", f"Deleted customer {user.get('phone', '')} ({user_id})")
    return {"status": "deleted"}


# ─── Orders ───────────────────────────────────────────────

@router.get("/orders")
async def list_orders(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str = Query(""),
    q: str = Query(""),
    admin: dict = Depends(get_current_admin),
):
    skip = (page - 1) * limit
    query: dict = {}
    if status:
        query["order_status"] = status
    if q:
        query["$or"] = [
            {"order_id": {"$regex": re.escape(q), "$options": "i"}},
            {"customer_id": {"$regex": re.escape(q), "$options": "i"}},
        ]
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    orders = [serialize(o) async for o in cursor]
    return {"orders": orders, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.put("/orders/{order_id}/status")
async def update_order_status(order_id: str, status: str = Body(..., embed=True), admin: dict = Depends(get_current_admin)):
    valid = ["Pending", "Confirmed", "Packed", "Out For Delivery", "Delivered", "Cancelled"]
    if status not in valid:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {valid}")
    now = _now()
    match = {"$or": [{"order_id": order_id}, {"_id": ObjectId(order_id)}]} if ObjectId.is_valid(order_id) else {"order_id": order_id}

    # Cancelling here has to put the goods back, exactly as the two handlers in
    # routes_orders.py do. This one did not, and it is the only route the panel
    # offers — and the app has no customer cancel button — so every cancelled
    # order used to lose its stock for good.
    existing = await orders_collection.find_one(match)
    if not existing:
        raise HTTPException(status_code=404, detail="Order not found")
    if should_release(existing, status):
        await release_stock(existing.get("items", []))

    await orders_collection.update_one(
        match,
        {
            "$set": {"order_status": status, "status": status.lower().replace(" ", "_"), "updated_at": now},
            "$push": {"status_history": {"status": status, "timestamp": now}},
        },
    )
    await _log(admin["email"], "order_status_updated", f"Order {order_id} -> {status}")

    # Delivered is announced to the owner and the customer alike. Every route
    # that can set it calls the same helper — three of them can, and the last
    # time three siblings each did their own thing, cancelling an order lost
    # its stock for months.
    if status == "Delivered" and existing.get("order_status") != "Delivered":
        await order_delivered({**existing, "order_status": status})

    # When the owner marks an order Packed, alert delivery staff
    if status == "Packed":
        order = await orders_collection.find_one(match)
        if order:
            try:
                notify_delivery_ready(order)
            except Exception as e:
                log.warning("Delivery push notify failed: %s", e)
    return {"status": status}


# ─── Delivery (staff role) ────────────────────────────────

@router.get("/delivery/orders")
async def delivery_orders(admin: dict = Depends(get_current_admin)):
    # Orders that are packed, out for delivery, or assigned to this staff.
    #
    # Newest first. It used to be oldest first, which put the order a driver had
    # just been notified about at the bottom of the list, below ones already
    # seen — they had to scroll to find the thing the notification was about.
    # The trade is that a strict queue would deliver the longest-waiting order
    # first; at this shop's volume the driver can see the whole list, so
    # matching the notification matters more than the ordering being a queue.
    # `orders.updated_at` is indexed, and the index serves either direction.
    query = {"order_status": {"$in": ["Packed", "Out For Delivery"]}}
    cursor = orders_collection.find(query).sort("updated_at", -1)
    orders = [serialize(o) async for o in cursor]
    return {"orders": orders, "total": len(orders)}


def _order_match(order_id: str) -> dict:
    if ObjectId.is_valid(order_id):
        return {"$or": [{"order_id": order_id}, {"_id": ObjectId(order_id)}]}
    return {"order_id": order_id}


@router.put("/delivery/orders/{order_id}/pickup")
async def delivery_pickup(order_id: str, admin: dict = Depends(get_current_admin)):
    now = _now()
    res = await orders_collection.update_one(
        _order_match(order_id),
        {
            "$set": {
                "order_status": "Out For Delivery",
                "status": "out_for_delivery",
                "updated_at": now,
                "tracking.assigned_delivery_partner": admin.get("name", admin.get("email", "")),
            },
            "$push": {"status_history": {"status": "Out For Delivery", "timestamp": now}},
        },
    )
    if res.matched_count == 0:
        raise HTTPException(status_code=404, detail="Order not found")
    await _log(admin["email"], "order_pickup", f"Picked up order {order_id}")
    return {"status": "Out For Delivery"}


@router.put("/delivery/orders/{order_id}/delivered")
async def delivery_delivered(order_id: str, admin: dict = Depends(get_current_admin)):
    now = _now()
    res = await orders_collection.update_one(
        _order_match(order_id),
        {
            "$set": {"order_status": "Delivered", "status": "delivered", "updated_at": now},
            "$push": {"status_history": {"status": "Delivered", "timestamp": now}},
        },
    )
    if res.matched_count == 0:
        raise HTTPException(status_code=404, detail="Order not found")
    await _log(admin["email"], "order_delivered", f"Delivered order {order_id}")

    order = await orders_collection.find_one(_order_match(order_id))
    if order:
        await order_delivered(order)
    return {"status": "Delivered"}


# ─── Audit Logs ───────────────────────────────────────────

@router.get("/logs")
async def get_audit_logs(
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    admin: dict = Depends(get_current_admin),
):
    skip = (page - 1) * limit
    total = await audit_logs_collection.count_documents({})
    cursor = audit_logs_collection.find().sort("timestamp", -1).skip(skip).limit(limit)
    logs = [serialize(l) async for l in cursor]
    return {"logs": logs, "total": total, "page": page, "pages": (total + limit - 1) // limit}
