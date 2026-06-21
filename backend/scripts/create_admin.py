"""
Create the initial admin account.

Usage:
  python scripts/create_admin.py

Default credentials:
  Email: admin@dhanamstore.com
  Password: ChangeMe123!
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import admins_collection
from admin_auth import hash_password


async def main():
    email = "admin@dhanamstore.com"
    password = "ChangeMe123!"

    existing = await admins_collection.find_one({"email": email})
    if existing:
        print(f"Admin account already exists: {email}")
        return

    await admins_collection.insert_one({
        "email": email,
        "password": hash_password(password),
        "name": "Dhanam Admin",
        "must_change_password": True,
        "created_at": __import__("datetime").datetime.utcnow().isoformat(),
    })

    print(f"Admin account created!")
    print(f"  Email:    {email}")
    print(f"  Password: {password}")
    print(f"  ** You must change this password on first login **")


if __name__ == "__main__":
    asyncio.run(main())
