from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import settings
from database import admins_collection

_security = HTTPBearer(auto_error=False)

ADMIN_JWT_SECRET = settings.jwt_secret + "-admin"
ADMIN_JWT_EXPIRY_HOURS = 24


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())


def create_admin_token(admin_id: str, email: str) -> str:
    payload = {
        "sub": admin_id,
        "email": email,
        "role": "admin",
        "exp": datetime.now(timezone.utc) + timedelta(hours=ADMIN_JWT_EXPIRY_HOURS),
    }
    return jwt.encode(payload, ADMIN_JWT_SECRET, algorithm="HS256")


def decode_admin_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, ADMIN_JWT_SECRET, algorithms=["HS256"])
        if payload.get("role") != "admin":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not an admin token")
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid admin token")


async def get_current_admin(
    credentials: HTTPAuthorizationCredentials | None = Depends(_security),
) -> dict:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin authentication required")
    payload = decode_admin_token(credentials.credentials)
    admin = await admins_collection.find_one({"email": payload["email"]})
    if not admin:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin not found")
    admin["id"] = str(admin.pop("_id"))
    return admin
