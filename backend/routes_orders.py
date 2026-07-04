import io
import re
import logging
from datetime import datetime, timedelta
from typing import Literal
from fastapi import APIRouter, Query, HTTPException, Body
from fastapi.responses import StreamingResponse
from bson import ObjectId
from fpdf import FPDF
from pydantic import BaseModel, Field
from database import orders_collection, products_collection, customers_collection, users_collection

log = logging.getLogger(__name__)
from push_service import notify_new_order

router = APIRouter()

VALID_STATUSES = ["Pending", "Confirmed", "Packed", "Out For Delivery", "Delivered", "Cancelled", "Refund Initiated", "Refund Completed"]


class OrderItem(BaseModel):
    product_id: str
    name: str = ""
    price: float = Field(gt=0)
    quantity: int = Field(gt=0)
    image: str = ""


class OrderAddress(BaseModel):
    full_name: str = ""
    phone: str = ""
    house_no: str = ""
    street: str = ""
    city: str = ""
    state: str = ""
    pincode: str = ""
    label: str = ""
    latitude: float = 0
    longitude: float = 0

    class Config:
        extra = "allow"


class CreateOrderRequest(BaseModel):
    user_id: str
    items: list[OrderItem] = Field(min_length=1)
    address: OrderAddress
    delivery_slot: str = Field(min_length=1)
    payment_method: Literal["cod"] = "cod"


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

async def _gst_rates_by_product(product_ids: list[str]) -> dict[str, float]:
    """Look up each product's own GST rate from the DB — never trust a
    client-sent rate, even though it only affects the informational
    breakdown (item prices are already GST-inclusive and drive the total)."""
    oids = [ObjectId(pid) for pid in product_ids if ObjectId.is_valid(pid)]
    if not oids:
        return {}
    rates: dict[str, float] = {}
    cursor = products_collection.find({"_id": {"$in": oids}}, {"gst": 1})
    async for doc in cursor:
        rates[str(doc["_id"])] = doc.get("gst", 0) or 0
    return rates


@router.post("/orders/create")
async def create_order(data: CreateOrderRequest):
    gst_rates = await _gst_rates_by_product([i.product_id for i in data.items])

    items = []
    gst_included = 0.0
    for item in data.items:
        d = item.model_dump()
        item_subtotal = round(item.price * item.quantity, 2)
        d["subtotal"] = item_subtotal
        items.append(d)
        rate = gst_rates.get(item.product_id, 0)
        if rate > 0:
            gst_included += item_subtotal * rate / (100 + rate)

    # `price` is already GST-inclusive per item (5% for most groceries, 0%
    # for some) — `gst` below is only the tax portion broken out for
    # display/invoicing and must NOT be added again into total_amount.
    subtotal = round(sum(i["subtotal"] for i in items), 2)
    gst = round(gst_included, 2)
    delivery_fee = 0 if subtotal >= 499 else 30
    discount = 0
    total_amount = round(subtotal + delivery_fee - discount, 2)

    now = _now()
    order_id = await _next_order_id()

    order = {
        "order_id": order_id,
        "customer_id": data.user_id,
        "user_id": data.user_id,
        "items": items,
        "delivery_address": data.address.model_dump(),
        "delivery_slot": data.delivery_slot,
        "payment_method": data.payment_method,
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

    # Notify the shop owner of the new order
    try:
        notify_new_order(order)
    except Exception as e:
        log.warning("Push notification for new order failed: %s", e)

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

def _build_invoice_pdf(order: dict) -> bytes:
    pdf = FPDF()
    pdf.add_page()
    pw = pdf.w - pdf.l_margin - pdf.r_margin

    # Header
    pdf.set_fill_color(13, 71, 161)
    pdf.rect(0, 0, pdf.w, 44, "F")
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 22)
    pdf.set_y(10)
    pdf.cell(pw, 10, "DHANAM STORE", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(pw, 8, "Tax Invoice", align="C", new_x="LMARGIN", new_y="NEXT")

    # Order info
    pdf.set_text_color(0, 0, 0)
    pdf.set_y(52)
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(pw / 2, 7, f"Order: {order.get('order_id', '')}")
    pdf.cell(pw / 2, 7, f"Date: {order.get('created_at', '')[:10]}", align="R", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(pw / 2, 6, f"Status: {order.get('order_status', '')}")
    pdf.cell(pw / 2, 6, f"Payment: {(order.get('payment_method') or 'N/A').upper()}", align="R", new_x="LMARGIN", new_y="NEXT")

    # Delivery address
    addr = order.get("delivery_address") or {}
    if addr:
        pdf.ln(4)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(pw, 6, "Delivery Address", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 9)
        name = addr.get("full_name") or addr.get("label") or ""
        line1 = addr.get("line1") or addr.get("house_no") or ""
        city = addr.get("city", "")
        state = addr.get("state", "")
        pincode = addr.get("pincode", "")
        phone = addr.get("phone", "")
        if name:
            pdf.cell(pw, 5, name, new_x="LMARGIN", new_y="NEXT")
        if line1 or city:
            pdf.cell(pw, 5, f"{line1}, {city}" if line1 else city, new_x="LMARGIN", new_y="NEXT")
        if state or pincode:
            pdf.cell(pw, 5, f"{state} - {pincode}", new_x="LMARGIN", new_y="NEXT")
        if phone:
            pdf.cell(pw, 5, f"Phone: {phone}", new_x="LMARGIN", new_y="NEXT")

    # Items table
    pdf.ln(6)
    col_name = pw * 0.50
    col_qty = pw * 0.12
    col_price = pw * 0.19
    col_total = pw * 0.19

    pdf.set_fill_color(240, 240, 245)
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(col_name, 9, "  Item", border=0, fill=True)
    pdf.cell(col_qty, 9, "Qty", border=0, fill=True, align="C")
    pdf.cell(col_price, 9, "Price", border=0, fill=True, align="R")
    pdf.cell(col_total, 9, "Total", border=0, fill=True, align="R", new_x="LMARGIN", new_y="NEXT")

    pdf.set_font("Helvetica", "", 9)
    for i, item in enumerate(order.get("items", [])):
        name = (item.get("product_name") or item.get("name", ""))[:40]
        qty = item.get("quantity", 0)
        price = item.get("price", 0)
        total = qty * price
        if i % 2 == 1:
            pdf.set_fill_color(248, 248, 252)
            fill = True
        else:
            fill = False
        pdf.cell(col_name, 8, f"  {name}", border=0, fill=fill)
        pdf.cell(col_qty, 8, str(qty), border=0, fill=fill, align="C")
        pdf.cell(col_price, 8, f"{price:,.2f}", border=0, fill=fill, align="R")
        pdf.cell(col_total, 8, f"{total:,.2f}", border=0, fill=fill, align="R", new_x="LMARGIN", new_y="NEXT")

    # Separator
    pdf.ln(2)
    pdf.set_draw_color(200, 200, 200)
    pdf.line(pdf.l_margin, pdf.get_y(), pdf.l_margin + pw, pdf.get_y())
    pdf.ln(4)

    # Summary
    sum_label_w = pw * 0.70
    sum_val_w = pw * 0.30
    pdf.set_font("Helvetica", "", 10)
    for label, val in [
        ("Subtotal (incl. GST)", order.get("subtotal", 0)),
        ("GST included", order.get("gst", 0)),
        ("Delivery Fee", order.get("delivery_fee", 0)),
    ]:
        pdf.cell(sum_label_w, 7, label, align="R")
        display = "FREE" if label == "Delivery Fee" and val == 0 else f"{val:,.2f}"
        pdf.cell(sum_val_w, 7, display, align="R", new_x="LMARGIN", new_y="NEXT")

    discount = order.get("discount", 0)
    if discount > 0:
        pdf.set_text_color(0, 150, 0)
        pdf.cell(sum_label_w, 7, "Discount", align="R")
        pdf.cell(sum_val_w, 7, f"-{discount:,.2f}", align="R", new_x="LMARGIN", new_y="NEXT")
        pdf.set_text_color(0, 0, 0)

    # Total
    pdf.ln(2)
    pdf.set_fill_color(13, 71, 161)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 13)
    grand = order.get("total_amount", order.get("grand_total", 0))
    pdf.cell(sum_label_w, 12, "TOTAL  ", align="R", fill=True)
    pdf.cell(sum_val_w, 12, f"  {grand:,.2f}  ", align="R", fill=True, new_x="LMARGIN", new_y="NEXT")

    # Footer
    pdf.set_text_color(120, 120, 120)
    pdf.set_font("Helvetica", "I", 9)
    pdf.ln(16)
    pdf.cell(pw, 6, "Thank you for shopping at Dhanam Store!", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 8)
    pdf.cell(pw, 5, "This is a computer-generated invoice and does not require a signature.", align="C")

    return pdf.output()


@router.get("/orders/{order_id}/invoice")
async def download_invoice(order_id: str):
    order = await orders_collection.find_one({"order_id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    pdf_bytes = _build_invoice_pdf(order)
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="invoice-{order_id}.pdf"'},
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
            {"order_id": {"$regex": re.escape(q), "$options": "i"}},
            {"customer_id": {"$regex": re.escape(q), "$options": "i"}},
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
