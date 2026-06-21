import re
from datetime import datetime
from pathlib import Path
from fastapi import APIRouter, Query, HTTPException, Request, Body, File, UploadFile
from bson import ObjectId
from database import customers_collection, orders_collection, wallet_transactions_collection, products_collection

router = APIRouter()

STATIC_DIR = Path(__file__).parent / "static"


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


async def _next_customer_id() -> str:
    last = await customers_collection.find_one(sort=[("customer_id", -1)])
    if last and last.get("customer_id"):
        num = int(last["customer_id"].replace("CUS", "")) + 1
    else:
        num = 1
    return f"CUS{num:06d}"


# ─── Registration & Profile ──────────────────────────────

@router.post("/customers/register")
async def register_customer(data: dict = Body(...)):
    phone = data.get("phone", "").strip()
    if not phone or len(phone) < 10:
        raise HTTPException(status_code=400, detail="Valid phone number required")

    existing = await customers_collection.find_one({"phone": phone})
    if existing:
        raise HTTPException(status_code=400, detail="Customer with this phone already exists")

    now = datetime.utcnow().isoformat()
    customer = {
        "customer_id": await _next_customer_id(),
        "name": data.get("name", ""),
        "email": data.get("email", ""),
        "phone": phone,
        "profile_image": "",
        "date_of_birth": data.get("date_of_birth", ""),
        "gender": data.get("gender", ""),
        "addresses": [],
        "wallet_balance": 0,
        "loyalty_points": 0,
        "wishlist": [],
        "cart": [],
        "order_history": [],
        "created_at": now,
        "updated_at": now,
        "is_active": True,
    }
    result = await customers_collection.insert_one(customer)
    return {"id": str(result.inserted_id), "customer_id": customer["customer_id"], "status": "registered"}


@router.get("/customers/{customer_id}")
async def get_customer(customer_id: str):
    customer = await customers_collection.find_one(
        {"$or": [{"customer_id": customer_id}, {"_id": ObjectId(customer_id) if ObjectId.is_valid(customer_id) else "x"}]}
    )
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    return serialize(customer)


@router.put("/customers/{customer_id}")
async def update_customer(customer_id: str, data: dict = Body(...)):
    allowed = {"name", "email", "date_of_birth", "gender"}
    update = {k: v for k, v in data.items() if k in allowed}
    update["updated_at"] = datetime.utcnow().isoformat()
    await customers_collection.update_one({"customer_id": customer_id}, {"$set": update})
    return {"status": "updated"}


@router.post("/customers/{customer_id}/profile-image")
async def upload_profile_image(customer_id: str, request: Request, file: UploadFile = File(...)):
    customer = await customers_collection.find_one({"customer_id": customer_id})
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    ext = Path(file.filename or "img.jpg").suffix or ".jpg"
    filename = f"profile-{customer_id.lower()}{ext}"
    (STATIC_DIR / "images" / "profiles").mkdir(parents=True, exist_ok=True)
    filepath = STATIC_DIR / "images" / "profiles" / filename
    filepath.write_bytes(await file.read())

    base_url = str(request.base_url).rstrip("/")
    image_url = f"{base_url}/static/images/profiles/{filename}"
    await customers_collection.update_one({"customer_id": customer_id}, {"$set": {"profile_image": image_url}})
    return {"status": "uploaded", "profile_image": image_url}


# ─── Addresses ────────────────────────────────────────────

@router.post("/customers/{customer_id}/addresses")
async def add_address(customer_id: str, address: dict = Body(...)):
    required = ["house_no", "street", "city", "state", "pincode"]
    for field in required:
        if not address.get(field):
            raise HTTPException(status_code=400, detail=f"{field} is required")

    address.setdefault("label", "Home")
    address.setdefault("is_default", False)
    address["id"] = str(ObjectId())

    if address.get("is_default"):
        await customers_collection.update_one(
            {"customer_id": customer_id},
            {"$set": {"addresses.$[].is_default": False}},
        )

    await customers_collection.update_one({"customer_id": customer_id}, {"$push": {"addresses": address}})
    return {"status": "added", "address_id": address["id"]}


@router.put("/customers/{customer_id}/addresses/{address_id}")
async def edit_address(customer_id: str, address_id: str, data: dict = Body(...)):
    update_fields = {}
    for k, v in data.items():
        update_fields[f"addresses.$.{k}"] = v
    update_fields["updated_at"] = datetime.utcnow().isoformat()
    await customers_collection.update_one(
        {"customer_id": customer_id, "addresses.id": address_id},
        {"$set": update_fields},
    )
    return {"status": "updated"}


@router.delete("/customers/{customer_id}/addresses/{address_id}")
async def delete_address(customer_id: str, address_id: str):
    await customers_collection.update_one(
        {"customer_id": customer_id},
        {"$pull": {"addresses": {"id": address_id}}},
    )
    return {"status": "deleted"}


@router.put("/customers/{customer_id}/addresses/{address_id}/default")
async def set_default_address(customer_id: str, address_id: str):
    await customers_collection.update_one(
        {"customer_id": customer_id},
        {"$set": {"addresses.$[].is_default": False}},
    )
    await customers_collection.update_one(
        {"customer_id": customer_id, "addresses.id": address_id},
        {"$set": {"addresses.$.is_default": True}},
    )
    return {"status": "default_set"}


# ─── Order History, Wishlist, Cart ────────────────────────

@router.get("/customers/{customer_id}/orders")
async def customer_orders(customer_id: str, page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=100)):
    skip = (page - 1) * limit
    customer = await customers_collection.find_one({"customer_id": customer_id}, {"order_history": 1})
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    query = {"user_id": customer_id}
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    orders = [serialize(o) async for o in cursor]
    return {"orders": orders, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.get("/customers/{customer_id}/wishlist")
async def customer_wishlist(customer_id: str):
    customer = await customers_collection.find_one({"customer_id": customer_id}, {"wishlist": 1})
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    return {"wishlist": customer.get("wishlist", [])}


@router.get("/customers/{customer_id}/cart")
async def customer_cart(customer_id: str):
    customer = await customers_collection.find_one({"customer_id": customer_id}, {"cart": 1})
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    return {"cart": customer.get("cart", [])}


# ─── Loyalty Points ──────────────────────────────────────

@router.post("/customers/{customer_id}/loyalty/add")
async def add_loyalty_points(customer_id: str, points: int = Body(..., embed=True), reason: str = Body("purchase", embed=True)):
    if points <= 0:
        raise HTTPException(status_code=400, detail="Points must be positive")
    await customers_collection.update_one(
        {"customer_id": customer_id},
        {"$inc": {"loyalty_points": points}, "$set": {"updated_at": datetime.utcnow().isoformat()}},
    )
    return {"status": "added", "points": points, "reason": reason}


@router.post("/customers/{customer_id}/loyalty/redeem")
async def redeem_loyalty_points(customer_id: str, points: int = Body(..., embed=True)):
    customer = await customers_collection.find_one({"customer_id": customer_id})
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    if customer.get("loyalty_points", 0) < points:
        raise HTTPException(status_code=400, detail="Insufficient loyalty points")
    await customers_collection.update_one(
        {"customer_id": customer_id},
        {"$inc": {"loyalty_points": -points}, "$set": {"updated_at": datetime.utcnow().isoformat()}},
    )
    return {"status": "redeemed", "points": points}


# ─── Wallet ──────────────────────────────────────────────

@router.post("/customers/{customer_id}/wallet/credit")
async def wallet_credit(customer_id: str, amount: float = Body(..., embed=True), reason: str = Body("top_up", embed=True)):
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")
    now = datetime.utcnow().isoformat()
    await customers_collection.update_one(
        {"customer_id": customer_id},
        {"$inc": {"wallet_balance": amount}, "$set": {"updated_at": now}},
    )
    await wallet_transactions_collection.insert_one({
        "customer_id": customer_id, "type": "credit", "amount": amount,
        "reason": reason, "created_at": now,
    })
    return {"status": "credited", "amount": amount}


@router.post("/customers/{customer_id}/wallet/debit")
async def wallet_debit(customer_id: str, amount: float = Body(..., embed=True), reason: str = Body("purchase", embed=True)):
    customer = await customers_collection.find_one({"customer_id": customer_id})
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    if customer.get("wallet_balance", 0) < amount:
        raise HTTPException(status_code=400, detail="Insufficient wallet balance")
    now = datetime.utcnow().isoformat()
    await customers_collection.update_one(
        {"customer_id": customer_id},
        {"$inc": {"wallet_balance": -amount}, "$set": {"updated_at": now}},
    )
    await wallet_transactions_collection.insert_one({
        "customer_id": customer_id, "type": "debit", "amount": amount,
        "reason": reason, "created_at": now,
    })
    return {"status": "debited", "amount": amount}


@router.get("/customers/{customer_id}/wallet/transactions")
async def wallet_transactions(customer_id: str, page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=50)):
    skip = (page - 1) * limit
    total = await wallet_transactions_collection.count_documents({"customer_id": customer_id})
    cursor = wallet_transactions_collection.find({"customer_id": customer_id}).sort("created_at", -1).skip(skip).limit(limit)
    txns = [serialize(t) async for t in cursor]
    return {"transactions": txns, "total": total, "page": page, "pages": (total + limit - 1) // limit}


# ─── Admin: Customer Management ──────────────────────────

@router.get("/admin/customers")
async def admin_list_customers(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    q: str = Query(""),
    status: str = Query(""),
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
    elif status == "inactive":
        query["is_active"] = False

    total = await customers_collection.count_documents(query)
    cursor = customers_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    customers = [serialize(c) async for c in cursor]
    return {"customers": customers, "total": total, "page": page, "pages": (total + limit - 1) // limit}


@router.get("/admin/customers/{customer_id}/orders")
async def admin_customer_orders(customer_id: str):
    cursor = orders_collection.find({"user_id": customer_id}).sort("created_at", -1)
    orders = [serialize(o) async for o in cursor]
    total_spending = sum(o.get("grand_total", 0) for o in orders)
    return {"orders": orders, "total_orders": len(orders), "total_spending": total_spending}


@router.put("/admin/customers/{customer_id}/block")
async def block_customer(customer_id: str):
    await customers_collection.update_one({"customer_id": customer_id}, {"$set": {"is_active": False, "updated_at": datetime.utcnow().isoformat()}})
    return {"status": "blocked"}


@router.put("/admin/customers/{customer_id}/activate")
async def activate_customer(customer_id: str):
    await customers_collection.update_one({"customer_id": customer_id}, {"$set": {"is_active": True, "updated_at": datetime.utcnow().isoformat()}})
    return {"status": "activated"}


@router.get("/admin/customers/top-spenders")
async def top_spenders(limit: int = Query(10, ge=1, le=50)):
    pipeline = [
        {"$group": {"_id": "$user_id", "total_spent": {"$sum": "$grand_total"}, "order_count": {"$sum": 1}}},
        {"$sort": {"total_spent": -1}},
        {"$limit": limit},
    ]
    results = []
    async for doc in orders_collection.aggregate(pipeline):
        customer = await customers_collection.find_one({"customer_id": doc["_id"]})
        results.append({
            "customer_id": doc["_id"],
            "name": customer.get("name", "") if customer else "",
            "phone": customer.get("phone", "") if customer else "",
            "total_spent": doc["total_spent"],
            "order_count": doc["order_count"],
        })
    return {"top_spenders": results}


@router.get("/admin/customers/export-csv")
async def export_customers_csv():
    from fastapi.responses import StreamingResponse
    import csv, io

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["customer_id", "name", "email", "phone", "gender", "wallet_balance", "loyalty_points", "is_active", "created_at"])

    async for c in customers_collection.find().sort("created_at", -1):
        writer.writerow([
            c.get("customer_id", ""), c.get("name", ""), c.get("email", ""),
            c.get("phone", ""), c.get("gender", ""), c.get("wallet_balance", 0),
            c.get("loyalty_points", 0), c.get("is_active", True), c.get("created_at", ""),
        ])

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=customers.csv"},
    )


# ─── Analytics ────────────────────────────────────────────

@router.get("/admin/customers/analytics")
async def customer_analytics():
    total = await customers_collection.count_documents({})
    active = await customers_collection.count_documents({"is_active": True})

    now = datetime.utcnow()
    month_start = datetime(now.year, now.month, 1).isoformat()
    new_this_month = await customers_collection.count_documents({"created_at": {"$gte": month_start}})

    revenue_pipeline = [
        {"$group": {"_id": "$user_id", "total": {"$sum": "$grand_total"}, "count": {"$sum": 1}}},
        {"$sort": {"total": -1}},
        {"$limit": 5},
    ]
    top_customers = []
    async for doc in orders_collection.aggregate(revenue_pipeline):
        cust = await customers_collection.find_one({"customer_id": doc["_id"]})
        top_customers.append({
            "customer_id": doc["_id"],
            "name": cust.get("name", "") if cust else "Unknown",
            "total_revenue": doc["total"],
            "orders": doc["count"],
        })

    product_pipeline = [
        {"$unwind": "$items"},
        {"$group": {"_id": "$items.name", "total_qty": {"$sum": "$items.quantity"}}},
        {"$sort": {"total_qty": -1}},
        {"$limit": 5},
    ]
    most_ordered = []
    async for doc in orders_collection.aggregate(product_pipeline):
        most_ordered.append({"name": doc["_id"], "quantity": doc["total_qty"]})

    total_revenue_pipeline = [{"$group": {"_id": None, "total": {"$sum": "$grand_total"}}}]
    total_revenue = 0.0
    async for doc in orders_collection.aggregate(total_revenue_pipeline):
        total_revenue = doc.get("total", 0)

    avg_revenue = total_revenue / total if total > 0 else 0

    return {
        "total_customers": total,
        "active_customers": active,
        "inactive_customers": total - active,
        "new_this_month": new_this_month,
        "top_customers": top_customers,
        "most_ordered_products": most_ordered,
        "total_revenue": total_revenue,
        "avg_revenue_per_customer": round(avg_revenue, 2),
    }
