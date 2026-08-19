"""Push must work when something else already built the Firebase app.

auth.py builds the default Firebase app on every customer login, to verify
phone tokens. push_service built its own, unconditionally — so the second one
to run raised "The default Firebase app already exists", the bare except
swallowed it, and _ready latched. Push was then silently off for the life of
the process while login carried on working.

Logins are constant and pushes are occasional, so in production auth always won
and delivery staff never got a notification. Found on 2026-08-18 by marking an
order Packed and watching nothing arrive, while the same topic push sent from a
laptop — a fresh process, no default app — arrived fine. That difference is the
whole bug, and it is why this is tested with a fake firebase_admin rather than
against a real one: the ordering is the thing under test.
"""
import sys
import types

import pytest


class _FakeApp:
    pass


def _fake_firebase(monkeypatch, *, already_initialized: bool):
    """Stand in for firebase_admin, recording initialize_app calls."""
    calls = []

    fb = types.ModuleType("firebase_admin")
    fb._apps = {"[DEFAULT]": _FakeApp()} if already_initialized else {}

    def initialize_app(cred=None):
        if fb._apps:
            raise ValueError("The default Firebase app already exists.")
        calls.append(cred)
        fb._apps["[DEFAULT]"] = _FakeApp()
        return fb._apps["[DEFAULT]"]

    fb.initialize_app = initialize_app
    fb.get_app = lambda: fb._apps["[DEFAULT]"]

    creds = types.ModuleType("firebase_admin.credentials")
    creds.Certificate = lambda *a, **k: object()
    messaging = types.ModuleType("firebase_admin.messaging")

    monkeypatch.setitem(sys.modules, "firebase_admin", fb)
    monkeypatch.setitem(sys.modules, "firebase_admin.credentials", creds)
    monkeypatch.setitem(sys.modules, "firebase_admin.messaging", messaging)
    fb.credentials = creds
    fb.messaging = messaging
    return fb, calls


@pytest.fixture
def push(monkeypatch):
    import push_service
    monkeypatch.setattr(push_service, "_app", None)
    monkeypatch.setattr(push_service, "_messaging", None)
    monkeypatch.setattr(push_service, "_ready", False)
    return push_service


class TestInitialisationOrder:
    def test_push_works_when_login_initialised_firebase_first(self, push, monkeypatch):
        """The production order: a customer logs in, then an order is packed."""
        _fake_firebase(monkeypatch, already_initialized=True)
        monkeypatch.setenv("FIREBASE_CREDENTIALS", "")

        push._init()

        assert push._messaging is not None, (
            "push gave up because the Firebase app already existed — delivery "
            "staff get no notification, and nothing in the logs says why"
        )

    def test_push_still_initialises_when_it_is_first(self, push, monkeypatch):
        _fake_firebase(monkeypatch, already_initialized=False)
        monkeypatch.setenv("FIREBASE_CREDENTIALS", '{"type":"service_account"}')

        push._init()

        assert push._messaging is not None

    def test_a_failed_attempt_does_not_disable_push_forever(self, push, monkeypatch):
        """No credentials at first, then a login builds the app."""
        fb, _ = _fake_firebase(monkeypatch, already_initialized=False)
        monkeypatch.setenv("FIREBASE_CREDENTIALS", "")
        monkeypatch.setattr(push, "Path", _NoFile)

        push._init()
        assert push._messaging is None, "expected console mode with no credentials"

        # A customer logs in; auth.py builds the default app.
        fb._apps["[DEFAULT]"] = _FakeApp()
        push._init()

        assert push._messaging is not None, (
            "_ready latched on the failed attempt, so push stayed off for the "
            "life of the process even once Firebase was available"
        )


class _NoFile:
    """A Path stand-in whose files never exist."""
    def __init__(self, *a, **k):
        pass

    def __truediv__(self, other):
        return self

    @property
    def parent(self):
        return self

    def exists(self):
        return False
