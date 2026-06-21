import random
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import settings
from database import users_collection

security = HTTPBearer(auto_error=False)

_otp_store: dict[str, dict] = {}


def generate_otp(phone: str) -> str:
    otp = f"{random.randint(1000, 9999)}"
    _otp_store[phone] = {
        "otp": otp,
        "expires": datetime.now(timezone.utc) + timedelta(minutes=5),
    }
    return otp


def verify_otp(phone: str, otp: str) -> bool:
    entry = _otp_store.get(phone)
    if not entry:
        return False
    if datetime.now(timezone.utc) > entry["expires"]:
        _otp_store.pop(phone, None)
        return False
    if entry["otp"] != otp:
        return False
    _otp_store.pop(phone, None)
    return True


def create_token(user_id: str, phone: str) -> str:
    payload = {
        "sub": user_id,
        "phone": phone,
        "exp": datetime.now(timezone.utc) + timedelta(hours=settings.jwt_expiry_hours),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(security),
) -> dict:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    payload = decode_token(credentials.credentials)
    user = await users_collection.find_one({"phone": payload["phone"]})
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    user["id"] = str(user.pop("_id"))
    return user


async def get_optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(security),
) -> dict | None:
    if not credentials:
        return None
    try:
        return await get_current_user(credentials)
    except HTTPException:
        return None
