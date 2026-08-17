import logging
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEFAULT_JWT_SECRET = "dhanam-store-secret-change-in-production"

class Settings(BaseSettings):
    mongodb_uri: str
    database_name: str = "dhanam_store"
    jwt_secret: str = _DEFAULT_JWT_SECRET
    # 90 days. Every expiry costs a real OTP SMS, billed per message, and the
    # free allowance is a daily one — so session length is the dial that decides
    # whether logins are free. At 30 days a customer needed ~1 SMS/month, which
    # for 10,000 customers is ~333/day against a free 357/day: inside, but with
    # no room. At 90 it is a third of that.
    #
    # Long sessions are safe here in a way they are not in most apps. The token
    # lives in the Android keystore, and `is_active` is checked on every request
    # rather than only at login — so blocking a customer in the panel locks them
    # out immediately, however long their token has left to run. A lost phone is
    # a support call, not a wait for expiry.
    #
    # Admin sessions are deliberately not this: ADMIN_JWT_EXPIRY_HOURS is 24.
    jwt_expiry_hours: int = 2160
    debug: bool = False
    # Same-origin by default: the admin panel is served by this app and the
    # mobile client doesn't enforce CORS, so nothing legitimate needs a wildcard.
    cors_origins: list[str] = []
    sentry_dsn: str = ""

    # Pincodes the shop actually delivers to. Empty means no restriction —
    # which is the current behaviour, and means an order can be placed from
    # anywhere in the country. Set DELIVERY_PINCODES to the real list.
    delivery_pincodes: list[str] = []

    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=False,
        extra="ignore",
    )

settings = Settings()

# The admin JWT secret is derived from this one (admin_auth.py), so leaving the
# default in place outside local dev would let anyone forge an admin token.
# Refuse to boot rather than serve traffic with a publicly-known signing key.
if settings.jwt_secret == _DEFAULT_JWT_SECRET and not settings.debug:
    raise RuntimeError(
        "JWT_SECRET is still the built-in default. Set a strong, random JWT_SECRET "
        "environment variable before starting the server (or set DEBUG=true for local dev)."
    )

if settings.jwt_secret == _DEFAULT_JWT_SECRET:
    logging.getLogger(__name__).warning(
        "Running in DEBUG with the default JWT_SECRET — never do this in production"
    )


if not settings.delivery_pincodes:
    logging.getLogger(__name__).warning(
        "DELIVERY_PINCODES is not set — orders will be accepted from any pincode in India"
    )
