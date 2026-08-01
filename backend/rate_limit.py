"""The shared rate limiter.

It lives here rather than in `main` so the routers can use it too — importing
it from `main` would be a cycle, since `main` imports every router.
"""
from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address


def client_ip(request: Request) -> str:
    """Resolve the real client IP behind Railway's proxy.

    Railway sets X-Forwarded-For; the first entry is the originating client.
    Falls back to the direct peer address for local and non-proxied requests.
    Without this every request appears to come from the proxy, and one
    customer's burst would rate-limit the whole shop.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return get_remote_address(request)


limiter = Limiter(key_func=client_ip)
