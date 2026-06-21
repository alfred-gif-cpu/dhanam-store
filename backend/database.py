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
wallet_transactions_collection = db["wallet_transactions"]
admins_collection = db["admins"]
audit_logs_collection = db["audit_logs"]
