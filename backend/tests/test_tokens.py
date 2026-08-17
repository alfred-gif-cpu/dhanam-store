"""Session and invoice tokens.

The login once issued a session for any phone number without verifying it.
The signing itself was never the weak part, but it is the thing everything
else rests on, so it is worth pinning: a token must survive a round trip,
and must not survive being altered.
"""
import time
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi import HTTPException

from auth import create_invoice_token, create_token, decode_token
from config import settings


class TestSessionTokens:
    def test_round_trip_preserves_the_caller(self):
        claims = decode_token(create_token("user-123", "+919876543210"))
        assert claims["sub"] == "user-123"
        assert claims["phone"] == "+919876543210"

    def test_a_token_carries_an_expiry(self):
        claims = decode_token(create_token("u", "+919876543210"))
        assert "exp" in claims, "a session token that never expires cannot be revoked"

    def test_a_customer_session_outlasts_an_admin_one_by_far(self):
        """Customer sessions are long on purpose; admin sessions must not follow.

        Every customer session that expires costs a real OTP SMS, so the length
        is a billing decision and it is set deliberately high — 90 days. That
        reasoning does not carry to the admin token, which opens the whole shop:
        the panel, every order, every customer record. If someone lengthens the
        customer session again and reaches for one shared constant, this is what
        should stop them.
        """
        from admin_auth import ADMIN_JWT_EXPIRY_HOURS

        assert settings.jwt_expiry_hours >= 24 * 30, (
            "customer sessions got short — each expiry bills an OTP SMS"
        )
        assert ADMIN_JWT_EXPIRY_HOURS <= 24, (
            "the admin token now lasts a day or more; a stolen laptop keeps the "
            "whole shop for that long"
        )
        assert ADMIN_JWT_EXPIRY_HOURS * 10 < settings.jwt_expiry_hours, (
            "admin and customer sessions have converged — they are set for "
            "opposite reasons and should not share a value"
        )

    def test_tampering_with_the_payload_is_rejected(self):
        token = create_token("user-123", "+919876543210")
        header, payload, signature = token.split(".")
        forged = jwt.encode({"sub": "somebody-else", "phone": "+910000000000",
                             "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
                            "the-wrong-secret", algorithm="HS256")
        with pytest.raises(HTTPException) as excinfo:
            decode_token(forged)
        assert excinfo.value.status_code == 401

    def test_an_expired_token_is_rejected(self):
        expired = jwt.encode(
            {"sub": "u", "phone": "+919876543210",
             "exp": datetime.now(timezone.utc) - timedelta(seconds=1)},
            settings.jwt_secret, algorithm="HS256")
        with pytest.raises(HTTPException) as excinfo:
            decode_token(expired)
        assert excinfo.value.status_code == 401

    @pytest.mark.parametrize("rubbish", ["", "abc", "a.b.c", "Bearer x", "null"])
    def test_rubbish_is_rejected_rather_than_crashing(self, rubbish):
        with pytest.raises(HTTPException):
            decode_token(rubbish)

    def test_the_algorithm_is_not_negotiable(self):
        """A token signed with "none" must not be accepted — the classic JWT
        forgery, and free to rule out."""
        unsigned = jwt.encode({"sub": "u", "phone": ""}, key="", algorithm="none")
        with pytest.raises(HTTPException):
            decode_token(unsigned)


class TestInvoiceTokens:
    """These travel in a URL to the system browser, where they land in
    history — so they are scoped to one order and expire quickly."""

    def test_scoped_to_one_order(self):
        claims = decode_token(create_invoice_token("ORD000042", "user-1"))
        assert claims.get("order_id") == "ORD000042"

    def test_expires_far_sooner_than_a_session(self):
        invoice = decode_token(create_invoice_token("ORD000042", "user-1"))
        session = decode_token(create_token("user-1", "+919876543210"))
        assert invoice["exp"] < session["exp"], (
            "an invoice link lives as long as a login — it should be minutes"
        )
        assert invoice["exp"] - time.time() < 3600, "invoice token lasts over an hour"
