from datetime import datetime
from fastapi import APIRouter, Query, HTTPException, Body, Depends
from bson import ObjectId
from database import db
from auth import get_current_user

router = APIRouter(tags=["Addresses"])

addresses_col = db["customer_addresses"]


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


async def _owned_address(address_id: str, user: dict) -> dict:
    """Fetch an address, but only if it belongs to the caller.

    A non-owned address returns 404 rather than 403: telling an attacker that
    an id exists but belongs to someone else is itself a disclosure, and
    ObjectIds are partly sequential so they can be walked.
    """
    if not ObjectId.is_valid(address_id):
        raise HTTPException(status_code=400, detail="Invalid address ID")
    addr = await addresses_col.find_one({"_id": ObjectId(address_id)})
    if not addr or addr.get("customer_id") != user["id"]:
        raise HTTPException(status_code=404, detail="Address not found")
    return addr


def _now() -> str:
    return datetime.utcnow().isoformat()


def _validate(data: dict):
    required = ["name", "phone", "house_no", "street", "city", "state", "pincode"]
    missing = [f for f in required if not data.get(f, "").strip()]
    if missing:
        raise HTTPException(status_code=400, detail=f"Missing required fields: {', '.join(missing)}")
    phone = data["phone"].strip()
    if len(phone) < 10 or not phone.replace("+", "").isdigit():
        raise HTTPException(status_code=400, detail="Invalid phone number")
    pincode = data["pincode"].strip()
    if len(pincode) != 6 or not pincode.isdigit():
        raise HTTPException(status_code=400, detail="Pincode must be 6 digits")


@router.post("/addresses")
async def add_address(data: dict = Body(...), user: dict = Depends(get_current_user)):
    # Taken from the verified token, not the body: a client-supplied
    # customer_id would let anyone file an address under another account.
    customer_id = user["id"]

    _validate(data)

    existing_count = await addresses_col.count_documents({"customer_id": customer_id})
    is_default = data.get("is_default", existing_count == 0)

    if is_default:
        await addresses_col.update_many(
            {"customer_id": customer_id},
            {"$set": {"is_default": False}},
        )

    address = {
        "customer_id": customer_id,
        "label": data.get("label", "Home"),
        "name": data["name"].strip(),
        "phone": data["phone"].strip(),
        "house_no": data["house_no"].strip(),
        "street": data["street"].strip(),
        "landmark": data.get("landmark", "").strip(),
        "area": data.get("area", "").strip(),
        "city": data["city"].strip(),
        "state": data["state"].strip(),
        "pincode": data["pincode"].strip(),
        "latitude": data.get("latitude", 0),
        "longitude": data.get("longitude", 0),
        "is_default": is_default,
        "created_at": _now(),
    }

    result = await addresses_col.insert_one(address)
    return {"id": str(result.inserted_id), "status": "created"}


@router.get("/addresses")
async def get_addresses(
    customer_id: str = Query("", description="ignored; kept so older clients still work"),
    user: dict = Depends(get_current_user),
):
    # The query parameter is deliberately ignored — callers only ever get
    # their own addresses, whatever they ask for.
    cursor = addresses_col.find({"customer_id": user["id"]}).sort("is_default", -1)
    addresses = [serialize(a) async for a in cursor]
    return {"addresses": addresses, "total": len(addresses)}


@router.get("/addresses/{address_id}")
async def get_address(address_id: str, user: dict = Depends(get_current_user)):
    return serialize(await _owned_address(address_id, user))


@router.put("/addresses/{address_id}")
async def update_address(
    address_id: str, data: dict = Body(...), user: dict = Depends(get_current_user)
):
    await _owned_address(address_id, user)

    allowed = {"label", "name", "phone", "house_no", "street", "landmark", "area",
               "city", "state", "pincode", "latitude", "longitude"}
    update = {k: v for k, v in data.items() if k in allowed}
    update["updated_at"] = _now()

    await addresses_col.update_one({"_id": ObjectId(address_id)}, {"$set": update})
    return {"status": "updated"}


@router.delete("/addresses/{address_id}")
async def delete_address(address_id: str, user: dict = Depends(get_current_user)):
    addr = await _owned_address(address_id, user)

    await addresses_col.delete_one({"_id": ObjectId(address_id)})

    if addr.get("is_default"):
        next_addr = await addresses_col.find_one({"customer_id": addr["customer_id"]})
        if next_addr:
            await addresses_col.update_one({"_id": next_addr["_id"]}, {"$set": {"is_default": True}})

    return {"status": "deleted"}


@router.put("/addresses/{address_id}/default")
async def set_default(address_id: str, user: dict = Depends(get_current_user)):
    addr = await _owned_address(address_id, user)

    await addresses_col.update_many(
        {"customer_id": addr["customer_id"]},
        {"$set": {"is_default": False}},
    )
    await addresses_col.update_one({"_id": ObjectId(address_id)}, {"$set": {"is_default": True}})
    return {"status": "default_set"}
