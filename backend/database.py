from motor.motor_asyncio import AsyncIOMotorClient
from config import settings

client = AsyncIOMotorClient(settings.mongodb_uri)
db = client[settings.database_name]

products_collection = db["products"]
banners_collection = db["banners"]
orders_collection = db["orders"]
addresses_collection = db["addresses"]
wishlists_collection = db["wishlists"]
users_collection = db["users"]
customers_collection = db["customers"]
admins_collection = db["admins"]
audit_logs_collection = db["audit_logs"]
otp_collection = db["otps"]
# Search terms that returned nothing — the term only, never who searched.
search_misses_collection = db["search_misses"]


async def ensure_indexes():
    await orders_collection.create_index("order_id", unique=True, sparse=True)
    await orders_collection.create_index("customer_id")
    await orders_collection.create_index("user_id")
    await orders_collection.create_index("created_at")
    await orders_collection.create_index("order_status")
    await products_collection.create_index("category")
    await products_collection.create_index([("name", 1)])
    await products_collection.create_index("search_text")
    await products_collection.create_index("search_words")
    await customers_collection.create_index("customer_id", unique=True, sparse=True)
    await customers_collection.create_index("phone", unique=True, sparse=True)
    await users_collection.create_index("phone", unique=True, sparse=True)
    await addresses_collection.create_index("user_id")
    await admins_collection.create_index("email", unique=True, sparse=True)
    await otp_collection.create_index("expires_at", expireAfterSeconds=0)
    # Sorted on by the admin order list; without this it is a full in-memory
    # sort of every order ever placed, which only gets slower.
    await orders_collection.create_index("updated_at")
    # /products/bestsellers sorts on this on every home screen load.
    await products_collection.create_index("sold_count")
    await banners_collection.create_index([("active", 1), ("order", 1)])
    await wishlists_collection.create_index("user_id")
    await audit_logs_collection.create_index("created_at")
    await search_misses_collection.create_index("term", unique=True, sparse=True)
