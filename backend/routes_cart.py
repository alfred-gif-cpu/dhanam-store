from datetime import datetime
from fastapi import APIRouter, Query, HTTPException, Body
from bson import ObjectId
from database import db

router = APIRouter(tags=["Cart"])

carts_col = db["carts"]
products_collection = db["products"]

FREE_DELIVERY_THRESHOLD = 499
DELIVERY_FEE = 30


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


def _now() -> str:
    return datetime.utcnow().isoformat()


async def _gst_rates_by_product(product_ids: list[str]) -> dict[str, float]:
    """Each item's own GST rate, looked up from the DB (never trusted from
    a client payload) — used only to break out the tax already included
    in `price`, never to add tax on top of it."""
    oids = [ObjectId(pid) for pid in product_ids if ObjectId.is_valid(pid)]
    if not oids:
        return {}
    rates: dict[str, float] = {}
    cursor = products_collection.find({"_id": {"$in": oids}}, {"gst": 1})
    async for doc in cursor:
        rates[str(doc["_id"])] = doc.get("gst", 0) or 0
    return rates


def _recalculate(cart: dict, gst_rates: dict[str, float] | None = None) -> dict:
    gst_rates = gst_rates or {}
    items = cart.get("items", [])
    for item in items:
        item["subtotal"] = round(item["price"] * item["quantity"], 2)

    # `price` is already GST-inclusive per item (5% for most groceries, 0%
    # for some) — `gst` below is only the tax portion broken out for
    # display and must NOT be added again into grand_total.
    subtotal = round(sum(i["subtotal"] for i in items), 2)
    gst = round(sum(
        i["subtotal"] * gst_rates.get(i["product_id"], 0) / (100 + gst_rates.get(i["product_id"], 0))
        for i in items if gst_rates.get(i["product_id"], 0) > 0
    ), 2)
    delivery_fee = 0 if subtotal >= FREE_DELIVERY_THRESHOLD else DELIVERY_FEE
    discount = cart.get("discount", 0)
    grand_total = round(subtotal + delivery_fee - discount, 2)

    cart.update({
        "items": items,
        "subtotal": subtotal,
        "gst": gst,
        "delivery_fee": delivery_fee,
        "discount": discount,
        "grand_total": grand_total,
        "item_count": sum(i["quantity"] for i in items),
        "unique_count": len(items),
        "savings": round(sum(
            (i.get("original_price", i["price"]) - i["price"]) * i["quantity"]
            for i in items if i.get("original_price", 0) > i["price"]
        ), 2),
        "free_delivery_remaining": max(0, round(FREE_DELIVERY_THRESHOLD - subtotal, 2)) if subtotal < FREE_DELIVERY_THRESHOLD else 0,
        "updated_at": _now(),
    })
    return cart


async def _recalc(cart: dict) -> dict:
    rates = await _gst_rates_by_product([i["product_id"] for i in cart.get("items", [])])
    return _recalculate(cart, rates)


async def _get_or_create_cart(customer_id: str) -> dict:
    cart = await carts_col.find_one({"customer_id": customer_id})
    if not cart:
        cart = {
            "customer_id": customer_id,
            "items": [],
            "subtotal": 0, "gst": 0, "delivery_fee": 0,
            "discount": 0, "grand_total": 0,
            "item_count": 0, "unique_count": 0, "savings": 0,
            "free_delivery_remaining": FREE_DELIVERY_THRESHOLD,
            "created_at": _now(), "updated_at": _now(),
        }
        result = await carts_col.insert_one(cart)
        cart["_id"] = result.inserted_id
    return cart


@router.get("/cart")
async def get_cart(customer_id: str = Query(...)):
    cart = await _get_or_create_cart(customer_id)
    return serialize(await _recalc(cart))


@router.post("/cart/add")
async def add_to_cart(
    customer_id: str = Body(...),
    product_id: str = Body(...),
    product_name: str = Body(""),
    price: float = Body(...),
    original_price: float = Body(0),
    quantity: int = Body(1),
    image: str = Body(""),
    category: str = Body(""),
):
    if quantity < 1:
        raise HTTPException(status_code=400, detail="Quantity must be at least 1")

    cart = await _get_or_create_cart(customer_id)
    items = cart.get("items", [])

    existing = next((i for i in items if i["product_id"] == product_id), None)
    if existing:
        existing["quantity"] += quantity
    else:
        items.append({
            "product_id": product_id,
            "product_name": product_name,
            "price": price,
            "original_price": original_price if original_price > 0 else price,
            "quantity": quantity,
            "image": image,
            "category": category,
            "subtotal": 0,
        })

    cart["items"] = items
    cart = await _recalc(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.put("/cart/update")
async def update_cart_item(
    customer_id: str = Body(...),
    product_id: str = Body(...),
    quantity: int = Body(...),
):
    cart = await _get_or_create_cart(customer_id)
    items = cart.get("items", [])

    if quantity <= 0:
        items = [i for i in items if i["product_id"] != product_id]
    else:
        item = next((i for i in items if i["product_id"] == product_id), None)
        if not item:
            raise HTTPException(status_code=404, detail="Product not in cart")
        item["quantity"] = quantity

    cart["items"] = items
    cart = await _recalc(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.delete("/cart/remove/{product_id}")
async def remove_from_cart(product_id: str, customer_id: str = Query(...)):
    cart = await _get_or_create_cart(customer_id)
    cart["items"] = [i for i in cart.get("items", []) if i["product_id"] != product_id]
    cart = await _recalc(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.delete("/cart/clear")
async def clear_cart(customer_id: str = Query(...)):
    cart = await _get_or_create_cart(customer_id)
    cart["items"] = []
    cart["discount"] = 0
    cart = await _recalc(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.post("/cart/sync")
async def sync_cart(customer_id: str = Body(...), items: list = Body(...)):
    cart = await _get_or_create_cart(customer_id)
    cart["items"] = items
    cart = await _recalc(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)
