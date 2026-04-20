"""Config parsing — DATABASE_URI, legacy envs, error paths."""
from __future__ import annotations

import pytest

from semantic_catalog.config import Settings, load_settings


def test_parse_uri_basic():
    s = load_settings(
        uri="teradata://demo_user:pw@host.example.com:1025/demo_user",
        env={},
    )
    assert isinstance(s, Settings)
    assert s.host == "host.example.com"
    assert s.user == "demo_user"
    assert s.password == "pw"
    assert s.port == 1025
    assert s.database == "demo_user"
    kw = s.driver_kwargs()
    assert kw["host"] == "host.example.com"
    assert kw["dbs_port"] == "1025"


def test_parse_uri_with_query_options():
    s = load_settings(
        uri="teradatasql://u:p@h/mydb?logmech=LDAP&tmode=TERA",
        env={},
    )
    assert s.extra == {"logmech": "LDAP", "tmode": "TERA"}
    assert "logmech" in s.driver_kwargs()


def test_uri_default_port_and_db():
    s = load_settings(uri="teradata://u:p@h", env={})
    assert s.port == 1025
    assert s.database == "demo_user"


def test_legacy_fallback():
    s = load_settings(env={
        "TERADATA_HOST": "h",
        "TERADATA_USER": "u",
        "TERADATA_PASSWORD": "p",
    })
    assert s.host == "h" and s.user == "u" and s.password == "p"


def test_error_when_nothing_set():
    with pytest.raises(RuntimeError):
        load_settings(env={})


def test_reject_wrong_scheme():
    with pytest.raises(ValueError):
        load_settings(uri="mysql://u:p@h/db", env={})


def test_bind_overrides():
    s = load_settings(uri="teradata://u:p@h/db",
                      env={"SC_BIND_HOST": "0.0.0.0", "SC_BIND_PORT": "9000"})
    assert s.bind_host == "0.0.0.0"
    assert s.bind_port == 9000
