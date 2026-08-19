"""Signing in with Google.

Free and unlimited, unlike the OTP path which bills per SMS — and it proves an
email, not a phone number. The shop is cash on delivery, so a phone is still
needed to hand goods over; it is collected at checkout and is not verified.

The thing most worth pinning is that signing in both ways reaches one account.
A customer who has ordered by phone for months and then taps Continue with
Google must not silently become a second customer with an empty order history.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import main
from main import app

TOKEN = "a-firebase-id-token"
GOOGLE = {"uid": "google-uid-1", "email": "felcia@gmail.com", "name": "Felcia"}


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    monkeypatch.setattr(main, "users_collection", db["users"])
    monkeypatch.setattr(main, "verify_firebase_google_token", lambda t: GOOGLE)
    monkeypatch.setattr(main.limiter, "enabled", False)
    return db


def _login(client):
    return client.post("/auth/google-login", json={"id_token": TOKEN})


@pytest.mark.asyncio
class TestGoogleLogin:
    async def test_a_new_customer_gets_an_account_and_a_session(self, client, shop):
        r = _login(client)

        assert r.status_code == 200
        body = r.json()
        assert body["is_new_user"] is True
        assert body["token"]
        assert body["needs_phone"] is True, (
            "a Google sign-in proves no phone number, and the shop cannot "
            "deliver without one"
        )

    async def test_signing_in_twice_does_not_make_two_customers(self, client, shop):
        first = _login(client).json()
        second = _login(client).json()

        assert first["user_id"] == second["user_id"]
        assert second["is_new_user"] is False
        assert await shop["users"].count_documents({}) == 1

    async def test_it_finds_the_account_they_already_had_by_phone(self, client, shop):
        existing = await shop["users"].insert_one({
            "phone": "+919489630602",
            "email": GOOGLE["email"],
            "name": "Felcia",
        })

        body = _login(client).json()

        assert body["user_id"] == str(existing.inserted_id), (
            "a customer with months of orders became a second, empty account "
            "the first time they tapped Continue with Google"
        )
        assert body["is_new_user"] is False
        assert body["needs_phone"] is False, "this account already has a phone"
        assert await shop["users"].count_documents({}) == 1

    async def test_the_google_account_is_linked_for_next_time(self, client, shop):
        await shop["users"].insert_one({
            "phone": "+919489630602", "email": GOOGLE["email"], "name": "Felcia",
        })
        _login(client)

        stored = await shop["users"].find_one({"email": GOOGLE["email"]})
        assert stored["google_uid"] == GOOGLE["uid"], (
            "without the link, matching depends on the email staying the same"
        )

    async def test_a_blocked_customer_is_refused(self, client, shop):
        await shop["users"].insert_one({
            "phone": "", "email": GOOGLE["email"], "google_uid": GOOGLE["uid"],
            "is_active": False,
        })

        r = _login(client)

        assert r.status_code == 403, (
            "blocking a customer must hold on every way in, or it holds on none"
        )


@pytest.mark.asyncio
class TestTheTokenIsTheOnlyProof:
    async def test_a_rejected_token_creates_nothing(self, client, shop, monkeypatch):
        from fastapi import HTTPException

        def reject(_):
            raise HTTPException(status_code=401, detail="Invalid or expired sign-in token")

        monkeypatch.setattr(main, "verify_firebase_google_token", reject)

        r = client.post("/auth/google-login", json={"id_token": "forged"})

        assert r.status_code == 401
        assert await shop["users"].count_documents({}) == 0, (
            "a forged token created a customer"
        )

    async def test_the_client_cannot_supply_its_own_email(self, client, shop):
        """Only the verified token decides who this is."""
        r = client.post("/auth/google-login",
                        json={"id_token": TOKEN, "email": "someone-else@gmail.com"})

        assert r.status_code == 200
        stored = await shop["users"].find_one({})
        assert stored["email"] == GOOGLE["email"]
