"""Test setup.

Two rules shape everything here:

  * no test touches a real database. The settings below point at an address
    nothing is listening on, and Motor connects lazily, so importing the app
    is safe. Anything that would issue a query is either not tested here or
    is tested through a path that rejects before reaching the database.
  * no test needs a network. They run the same on a laptop with no internet
    and in CI on a fresh runner.

That rules out end-to-end coverage of the ordering flow, which needs a real
Mongo. What it buys is a suite that runs in under a second and never fails
for a reason unrelated to the code.
"""
import os
import sys
from pathlib import Path

# Set before importing anything from the app: config.py reads these at import
# time and refuses to start on the default JWT secret outside debug.
os.environ.setdefault("MONGODB_URI", "mongodb://127.0.0.1:27017/dhanam_store_test")
os.environ.setdefault("DATABASE_NAME", "dhanam_store_test")
os.environ.setdefault("JWT_SECRET", "test-only-secret-never-used-in-production")
os.environ.setdefault("DEBUG", "true")
os.environ.setdefault("DELIVERY_PINCODES", '["635109","635110","635126"]')

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402


@pytest.fixture(scope="session")
def client() -> TestClient:
    """A client that never runs the app's lifespan.

    Deliberately not used as a context manager: entering one would fire the
    startup handler, which builds indexes and therefore needs a live
    database. Requests still route normally without it.
    """
    return TestClient(app)


@pytest.fixture(scope="session")
def tolerant_client() -> TestClient:
    """Returns server errors as responses instead of raising them.

    For the handful of tests that only care which side of the auth line a
    response falls on. Those endpoints go on to query the database, which
    these tests do not have, and the resulting error is not the point — a 500
    still answers the question, an exception does not.
    """
    return TestClient(app, raise_server_exceptions=False)
