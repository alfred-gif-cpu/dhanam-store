import os
import json
import random
import logging
from pathlib import Path
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import settings
from database import users_collection, otp_collection

log = logging.getLogger(__name__)
security = HTTPBearer(auto_error=False)


def _ensure_firebase_app() -> bool:
    """Initialize the Firebase Admin default app if it isn't already
    (shared credential source with push_service.py's FCM setup)."""
    import firebase_admin
    if firebase_admin._apps:
        return True
    from firebase_admin import credentials
    raw = os.environ.get("FIREBASE_CREDENTIALS", "").strip()
    if raw:
        cred = credentials.Certificate(json.loads(raw))
    else:
        path = Path(__file__).parent / "firebase-credentials.json"
        if not path.exists():
            return False
        cred = credentials.Certificate(str(path))
    firebase_admin.initialize_app(cred)
    return True


def verify_firebase_phone_token(id_token: str) -> str:
    """Verify a Firebase ID token server-side and return the phone number
    Firebase itself attests to. Never trust a client-supplied phone number
    for login — the token is the only proof of phone ownership."""
    if not _ensure_firebase_app():
        raise HTTPException(status_code=503, detail="Phone verification unavailable")
    from firebase_admin import auth as firebase_auth
    try:
        decoded = firebase_auth.verify_id_token(id_token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired verification token")
    phone = decoded.get("phone_number")
    if not phone:
        raise HTTPException(status_code=401, detail="Token is not phone-verified")
    return phone


async def generate_otp(phone: str) -> str:
    otp = f"{random.randint(1000, 9999)}"
    await otp_collection.update_one(
        {"phone": phone},
        {"$set": {
            "otp": otp,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
        }},
        upsert=True,
    )
    return otp


async def verify_otp(phone: str, otp: str) -> bool:
    entry = await otp_collection.find_one({"phone": phone})
    if not entry:
        return False
    if datetime.now(timezone.utc) > entry["expires_at"]:
        await otp_collection.delete_one({"phone": phone})
        return False
    if entry["otp"] != otp:
        return False
    await otp_collection.delete_one({"phone": phone})
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
