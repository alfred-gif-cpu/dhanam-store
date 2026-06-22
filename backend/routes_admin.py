import re
from datetime import datetime
from pathlib import Path
from fastapi import APIRouter, Query, HTTPException, Request, Body, Depends, File, UploadFile
from bson import ObjectId
from database import (
    admins_collection, audit_logs_collection, products_collection,
    orders_collection, customers_collection, users_collection,
)
from admin_auth import (
    hash_password, verify_password, create_admin_token, get_current_admin,
)
from push_service import notify_delivery_ready

router = APIRouter(prefix="/admin", tags=["Admin"])

STATIC_DIR = Path(__file__).parent / "static"


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
    total_customers = await customers_collection.count_documents({})
    total_users = await users_collection.count_documents({})
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
    admin: dict = Depends(get_current_admin),
):
    skip = (page - 1) * limit
    query: dict = {}
    if q:
        query["$or"] = [
            {"name": {"$regex": q, "$options": "i"}},
            {"brand": {"$regex": q, "$options": "i"}},
            {"category": {"$regex": q, "$options": "i"}},
        ]
    total = await products_collection.count_documents(query)
    cursor = products_collection.find(query).sort("name", 1).skip(skip).limit(limit)
    products = []
    base_url = str(request.base_url).rstrip("/")
    async for p in cursor:
        p["id"] = str(p.pop("_id"))
        img = p.get("image_url") or p.get("image") or ""
        if img and not img.startswith("http"):
            img = f"{base_url}/static/images/{img}"
        p["image"] = img
        products.append(p)
    return {"products": products, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.post("/products")
async def create_product(product: dict = Body(...), admin: dict = Depends(get_current_admin)):
    product["created_at"] = _now()
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

    ext = Path(file.filename or "img.jpg").suffix or ".jpg"
    slug = re.sub(r"[^a-z0-9]+", "-", product.get("name", "product").lower()).strip("-")
    filename = f"{slug}{ext}"
    (STATIC_DIR / "images").mkdir(parents=True, exist_ok=True)
    (STATIC_DIR / "images" / filename).write_bytes(await file.read())

    await products_collection.update_one({"_id": ObjectId(product_id)}, {"$set": {"image_url": filename}})
    base_url = str(request.base_url).rstrip("/")
    return {"status": "uploaded", "image_url": f"{base_url}/static/images/{filename}"}


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
    skip = (page - 1) * limit
    query: dict = {}
    if q:
        query["$or"] = [
            {"name": {"$regex": q, "$options": "i"}},
            {"phone": {"$regex": q, "$options": "i"}},
            {"email": {"$regex": q, "$options": "i"}},
            {"customer_id": {"$regex": q, "$options": "i"}},
        ]
    if status == "active":
        query["is_active"] = True
    elif status == "blocked":
        query["is_active"] = False

    total = await customers_collection.count_documents(query)
    cursor = customers_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    customers = [serialize(c) async for c in cursor]
    return {"customers": customers, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.put("/customers/{customer_id}/block")
async def block_customer(customer_id: str, admin: dict = Depends(get_current_admin)):
    await customers_collection.update_one({"customer_id": customer_id}, {"$set": {"is_active": False}})
    await _log(admin["email"], "customer_blocked", f"Blocked customer: {customer_id}")
    return {"status": "blocked"}


@router.put("/customers/{customer_id}/unblock")
async def unblock_customer(customer_id: str, admin: dict = Depends(get_current_admin)):
    await customers_collection.update_one({"customer_id": customer_id}, {"$set": {"is_active": True}})
    await _log(admin["email"], "customer_unblocked", f"Unblocked customer: {customer_id}")
    return {"status": "unblocked"}


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
            {"order_id": {"$regex": q, "$options": "i"}},
            {"customer_id": {"$regex": q, "$options": "i"}},
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
    await orders_collection.update_one(
        match,
        {
            "$set": {"order_status": status, "status": status.lower().replace(" ", "_"), "updated_at": now},
            "$push": {"status_history": {"status": status, "timestamp": now}},
        },
    )
    await _log(admin["email"], "order_status_updated", f"Order {order_id} -> {status}")

    # When the owner marks an order Packed, alert delivery staff
    if status == "Packed":
        order = await orders_collection.find_one(match)
        if order:
            try:
                notify_delivery_ready(order)
            except Exception as e:
                print(f"[PUSH] Delivery notify failed: {e}")
    return {"status": status}


# ─── Delivery (staff role) ────────────────────────────────

@router.get("/delivery/orders")
async def delivery_orders(admin: dict = Depends(get_current_admin)):
    # Orders that are packed, out for delivery, or assigned to this staff
    query = {"order_status": {"$in": ["Packed", "Out For Delivery"]}}
    cursor = orders_collection.find(query).sort("updated_at", 1)
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
