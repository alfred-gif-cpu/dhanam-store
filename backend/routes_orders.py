import io
from datetime import datetime, timedelta
from fastapi import APIRouter, Query, HTTPException, Body
from fastapi.responses import StreamingResponse
from bson import ObjectId
from database import orders_collection, products_collection, customers_collection, users_collection
from sms_service import send_order_receipt_sms

router = APIRouter()

VALID_STATUSES = ["Pending", "Confirmed", "Packed", "Out For Delivery", "Delivered", "Cancelled", "Refund Initiated", "Refund Completed"]


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


async def _next_order_id() -> str:
    last = await orders_collection.find_one(sort=[("order_id", -1)])
    if last and last.get("order_id", "").startswith("ORD"):
        num = int(last["order_id"].replace("ORD", "")) + 1
    else:
        num = 1
    return f"ORD{num:06d}"


def _now() -> str:
    return datetime.utcnow().isoformat()


# ─── Create Order ─────────────────────────────────────────

@router.post("/orders/create")
async def create_order(data: dict = Body(...)):
    items = data.get("items", [])
    if not items:
        raise HTTPException(status_code=400, detail="Order must have at least one item")

    for item in items:
        item["subtotal"] = round(item.get("price", 0) * item.get("quantity", 0), 2)

    subtotal = round(sum(i["subtotal"] for i in items), 2)
    gst = round(data.get("gst", subtotal * 0.18), 2)
    delivery_fee = data.get("delivery_fee", 0 if subtotal >= 499 else 30)
    discount = data.get("discount", 0)
    total_amount = round(subtotal + gst + delivery_fee - discount, 2)

    now = _now()
    order_id = await _next_order_id()

    order = {
        "order_id": order_id,
        "customer_id": data.get("customer_id", data.get("user_id", "")),
        "items": items,
        "delivery_address": data.get("delivery_address", data.get("address", {})),
        "delivery_slot": data.get("delivery_slot", ""),
        "payment_method": data.get("payment_method", "cod"),
        "payment_id": data.get("payment_id", ""),
        "razorpay_order_id": data.get("razorpay_order_id", ""),
        "subtotal": subtotal,
        "gst": gst,
        "delivery_fee": delivery_fee,
        "discount": discount,
        "total_amount": total_amount,
        "grand_total": total_amount,
        "order_status": "Confirmed",
        "status": "confirmed",
        "status_history": [{"status": "Pending", "timestamp": now}, {"status": "Confirmed", "timestamp": now}],
        "timeline": [{"status": "confirmed", "time": now, "message": "Order confirmed"}],
        "tracking": {
            "assigned_delivery_partner": "",
            "estimated_delivery_time": (datetime.utcnow() + timedelta(minutes=30)).isoformat(),
            "current_location": "",
        },
        "created_at": now,
        "updated_at": now,
    }

    result = await orders_collection.insert_one(order)

    # Send bill receipt via SMS to the order's phone number
    phone = ""
    addr = order.get("delivery_address", {})
    if isinstance(addr, dict):
        phone = addr.get("phone", "")
    if not phone:
        customer_id = data.get("customer_id", data.get("user_id", ""))
        if customer_id:
            try:
                user = await users_collection.find_one({"_id": ObjectId(customer_id)})
                if user:
                    phone = user.get("phone", "")
            except Exception:
                pass
    if phone:
        try:
            send_order_receipt_sms(phone, order)
        except Exception as e:
            print(f"[SMS] Receipt send failed: {e}")

    return {
        "id": str(result.inserted_id),
        "order_id": order_id,
        "order_number": order_id,
        "status": "Confirmed",
        "total_amount": total_amount,
        "estimated_delivery": order["tracking"]["estimated_delivery_time"],
    }


# ─── Get Order ────────────────────────────────────────────

@router.get("/orders/by-id/{order_id}")
async def get_order_by_id(order_id: str):
    order = await orders_collection.find_one(
        {"$or": [{"order_id": order_id}, {"_id": ObjectId(order_id) if ObjectId.is_valid(order_id) else "x"}]}
    )
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return serialize(order)


@router.get("/orders/customer/{customer_id}")
async def get_customer_orders(
    customer_id: str,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str = Query(""),
):
    skip = (page - 1) * limit
    query: dict = {"$or": [{"customer_id": customer_id}, {"user_id": customer_id}]}
    if status:
        query["order_status"] = status
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    orders = [serialize(o) async for o in cursor]
    return {"orders": orders, "total": total, "page": page, "pages": (total + limit - 1) // limit}


# ─── Cancel Order ─────────────────────────────────────────

@router.put("/orders/{order_id}/cancel")
async def cancel_order(order_id: str, reason: str = Body("Customer requested", embed=True)):
    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.get("order_status") in ["Delivered", "Cancelled", "Refund Completed"]:
        raise HTTPException(status_code=400, detail=f"Cannot cancel order with status: {order['order_status']}")

    now = _now()
    await orders_collection.update_one(
        {"order_id": order_id},
        {
            "$set": {"order_status": "Cancelled", "status": "cancelled", "updated_at": now, "cancel_reason": reason},
            "$push": {
                "status_history": {"status": "Cancelled", "timestamp": now},
                "timeline": {"status": "cancelled", "time": now, "message": f"Order cancelled: {reason}"},
            },
        },
    )
    return {"status": "Cancelled", "reason": reason}


# ─── Update Status ────────────────────────────────────────

@router.put("/orders/{order_id}/status")
async def update_order_status(order_id: str, status: str = Body(..., embed=True)):
    if status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {VALID_STATUSES}")

    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    now = _now()
    await orders_collection.update_one(
        {"order_id": order_id},
        {
            "$set": {"order_status": status, "status": status.lower().replace(" ", "_"), "updated_at": now},
            "$push": {
                "status_history": {"status": status, "timestamp": now},
                "timeline": {"status": status.lower().replace(" ", "_"), "time": now, "message": f"Order {status.lower()}"},
            },
        },
    )
    return {"status": status}


# ─── Tracking ─────────────────────────────────────────────

@router.get("/orders/{order_id}/track")
async def track_order(order_id: str):
    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return {
        "order_id": order["order_id"],
        "order_status": order.get("order_status", ""),
        "status_history": order.get("status_history", []),
        "tracking": order.get("tracking", {}),
        "estimated_delivery": order.get("tracking", {}).get("estimated_delivery_time", ""),
    }


@router.put("/orders/{order_id}/assign-partner")
async def assign_delivery_partner(order_id: str, partner_name: str = Body(..., embed=True)):
    now = _now()
    await orders_collection.update_one(
        {"order_id": order_id},
        {"$set": {"tracking.assigned_delivery_partner": partner_name, "updated_at": now}},
    )
    return {"status": "assigned", "partner": partner_name}


# ─── Filtered Lists ──────────────────────────────────────

@router.get("/orders/active")
async def get_active_orders(page: int = Query(1, ge=1), limit: int = Query(20)):
    skip = (page - 1) * limit
    query = {"order_status": {"$in": ["Pending", "Confirmed", "Packed", "Out For Delivery"]}}
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    return {"orders": [serialize(o) async for o in cursor], "total": total}


@router.get("/orders/delivered")
async def get_delivered_orders(page: int = Query(1, ge=1), limit: int = Query(20)):
    skip = (page - 1) * limit
    query = {"order_status": "Delivered"}
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    return {"orders": [serialize(o) async for o in cursor], "total": total}


@router.get("/orders/cancelled")
async def get_cancelled_orders(page: int = Query(1, ge=1), limit: int = Query(20)):
    skip = (page - 1) * limit
    query = {"order_status": {"$in": ["Cancelled", "Refund Initiated", "Refund Completed"]}}
    total = await orders_collection.count_documents(query)
    cursor = orders_collection.find(query).sort("created_at", -1).skip(skip).limit(limit)
    return {"orders": [serialize(o) async for o in cursor], "total": total}


# ─── Refund ───────────────────────────────────────────────

@router.put("/orders/{order_id}/refund")
async def initiate_refund(order_id: str):
    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.get("order_status") != "Cancelled":
        raise HTTPException(status_code=400, detail="Only cancelled orders can be refunded")

    now = _now()
    await orders_collection.update_one(
        {"order_id": order_id},
        {
            "$set": {"order_status": "Refund Initiated", "status": "refund_initiated", "updated_at": now},
            "$push": {"status_history": {"status": "Refund Initiated", "timestamp": now}},
        },
    )
    return {"status": "Refund Initiated"}


@router.put("/orders/{order_id}/refund-complete")
async def complete_refund(order_id: str):
    now = _now()
    await orders_collection.update_one(
        {"order_id": order_id},
        {
            "$set": {"order_status": "Refund Completed", "status": "refund_completed", "updated_at": now},
            "$push": {"status_history": {"status": "Refund Completed", "timestamp": now}},
        },
    )
    return {"status": "Refund Completed"}


# ─── Reorder ──────────────────────────────────────────────

@router.post("/orders/{order_id}/reorder")
async def reorder(order_id: str):
    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    new_items = []
    for item in order.get("items", []):
        new_items.append({
            "product_id": item.get("product_id", ""),
            "product_name": item.get("product_name", item.get("name", "")),
            "name": item.get("name", item.get("product_name", "")),
            "price": item.get("price", 0),
            "quantity": item.get("quantity", 0),
            "subtotal": item.get("price", 0) * item.get("quantity", 0),
        })

    return {
        "items": new_items,
        "delivery_address": order.get("delivery_address", {}),
        "payment_method": order.get("payment_method", "cod"),
    }


# ─── Invoice ─────────────────────────────────────────────

@router.get("/orders/{order_id}/invoice")
async def download_invoice(order_id: str):
    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    lines = [
        "=" * 50,
        "           DHANAM STORE - TAX INVOICE",
        "=" * 50,
        f"Order ID: {order.get('order_id', '')}",
        f"Date: {order.get('created_at', '')[:10]}",
        f"Status: {order.get('order_status', '')}",
        f"Payment: {order.get('payment_method', '')}",
        "-" * 50,
        f"{'Item':<25} {'Qty':>4} {'Price':>8} {'Total':>8}",
        "-" * 50,
    ]

    for item in order.get("items", []):
        name = (item.get("product_name") or item.get("name", ""))[:24]
        qty = item.get("quantity", 0)
        price = item.get("price", 0)
        total = qty * price
        lines.append(f"{name:<25} {qty:>4} {price:>8.2f} {total:>8.2f}")

    lines.extend([
        "-" * 50,
        f"{'Subtotal':>39} {order.get('subtotal', 0):>8.2f}",
        f"{'GST (18%)':>39} {order.get('gst', 0):>8.2f}",
        f"{'Delivery':>39} {order.get('delivery_fee', 0):>8.2f}",
    ])

    if order.get("discount", 0) > 0:
        lines.append(f"{'Discount':>39} -{order['discount']:>7.2f}")

    lines.extend([
        "=" * 50,
        f"{'TOTAL':>39} {order.get('total_amount', order.get('grand_total', 0)):>8.2f}",
        "=" * 50,
        "",
        "Thank you for shopping at Dhanam Store!",
    ])

    addr = order.get("delivery_address", {})
    if addr:
        lines.extend(["", "Delivery Address:", f"  {addr.get('full_name', addr.get('label', ''))}",
                       f"  {addr.get('line1', addr.get('house_no', ''))}, {addr.get('city', '')}",
                       f"  {addr.get('state', '')} - {addr.get('pincode', '')}"])

    content = "\n".join(lines)
    return StreamingResponse(
        iter([content]),
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=invoice-{order_id}.txt"},
    )


# ─── Admin: Order Management ─────────────────────────────

@router.get("/admin/orders/all")
async def admin_all_orders(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str = Query(""),
    q: str = Query(""),
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


# ─── Analytics ────────────────────────────────────────────

@router.get("/admin/orders/analytics")
async def order_analytics():
    now = datetime.utcnow()
    today_start = datetime(now.year, now.month, now.day).isoformat()
    month_start = datetime(now.year, now.month, 1).isoformat()

    total_orders = await orders_collection.count_documents({})
    orders_today = await orders_collection.count_documents({"created_at": {"$gte": today_start}})

    rev_today_pipeline = [
        {"$match": {"created_at": {"$gte": today_start}}},
        {"$group": {"_id": None, "total": {"$sum": {"$ifNull": ["$total_amount", "$grand_total"]}}}},
    ]
    revenue_today = 0.0
    async for doc in orders_collection.aggregate(rev_today_pipeline):
        revenue_today = doc.get("total", 0)

    rev_month_pipeline = [
        {"$match": {"created_at": {"$gte": month_start}}},
        {"$group": {"_id": None, "total": {"$sum": {"$ifNull": ["$total_amount", "$grand_total"]}}}},
    ]
    revenue_month = 0.0
    async for doc in orders_collection.aggregate(rev_month_pipeline):
        revenue_month = doc.get("total", 0)

    avg_pipeline = [{"$group": {"_id": None, "avg": {"$avg": {"$ifNull": ["$total_amount", "$grand_total"]}}}}]
    avg_order = 0.0
    async for doc in orders_collection.aggregate(avg_pipeline):
        avg_order = round(doc.get("avg", 0), 2)

    top_products_pipeline = [
        {"$unwind": "$items"},
        {"$group": {"_id": {"$ifNull": ["$items.product_name", "$items.name"]}, "qty": {"$sum": "$items.quantity"}, "revenue": {"$sum": "$items.subtotal"}}},
        {"$sort": {"qty": -1}},
        {"$limit": 10},
    ]
    top_products = []
    async for doc in orders_collection.aggregate(top_products_pipeline):
        top_products.append({"name": doc["_id"], "quantity": doc["qty"], "revenue": round(doc.get("revenue", 0), 2)})

    cancelled = await orders_collection.count_documents({"order_status": {"$in": ["Cancelled", "Refund Initiated", "Refund Completed"]}})
    delivered = await orders_collection.count_documents({"order_status": "Delivered"})

    cancel_rate = round(cancelled / total_orders * 100, 1) if total_orders > 0 else 0
    delivery_rate = round(delivered / total_orders * 100, 1) if total_orders > 0 else 0

    return {
        "total_orders": total_orders,
        "orders_today": orders_today,
        "revenue_today": round(revenue_today, 2),
        "revenue_this_month": round(revenue_month, 2),
        "avg_order_value": avg_order,
        "cancellation_rate": cancel_rate,
        "delivery_success_rate": delivery_rate,
        "top_selling_products": top_products,
    }
