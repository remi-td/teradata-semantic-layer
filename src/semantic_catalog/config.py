"""Environment configuration.

The primary knob is ``DATABASE_URI`` — the same contract used by the
Teradata MCP Server. The URI is parsed into connection parameters for the
``teradatasql`` driver.

Supported formats::

    teradata://<user>:<password>@<host>[:<port>]/<database>[?<opts>]
    teradatasql://<user>:<password>@<host>[:<port>]/<database>[?<opts>]

Query-string options (all optional) are forwarded as driver kwargs, e.g.
``?logmech=LDAP&tmode=TERA``.

Legacy knobs (``TERADATA_HOST``/``USER``/``PASSWORD``) still work as a
fallback when ``DATABASE_URI`` is absent.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, Optional
from urllib.parse import urlparse, parse_qs, unquote


@dataclass(frozen=True)
class Settings:
    host: str
    user: str
    password: str
    database: str = "demo_user"
    port: int = 1025
    extra: Dict[str, str] = field(default_factory=dict)

    # GUI server
    bind_host: str = "127.0.0.1"
    bind_port: int = 8080
    cors_allow_origins: str = "*"  # comma-separated

    @property
    def catalog_db(self) -> str:
        """The database where semantic catalog objects live."""
        return self.database

    def driver_kwargs(self) -> Dict[str, str]:
        kw = {
            "host": self.host,
            "user": self.user,
            "password": self.password,
            "dbs_port": str(self.port),
        }
        kw.update(self.extra)
        return kw


def _parse_uri(uri: str) -> Dict[str, str]:
    # Normalise scheme so urlparse picks up host/port reliably.
    if uri.startswith("teradata://"):
        uri = "teradatasql://" + uri[len("teradata://"):]
    parsed = urlparse(uri)
    if parsed.scheme not in {"teradatasql", "teradata"}:
        raise ValueError(
            f"DATABASE_URI must start with teradata:// or teradatasql:// (got {parsed.scheme!r})"
        )
    if not parsed.hostname:
        raise ValueError("DATABASE_URI is missing the host component")

    extras: Dict[str, str] = {}
    for k, v in parse_qs(parsed.query).items():
        extras[k] = v[0]

    database = (parsed.path or "/").lstrip("/") or "demo_user"
    return {
        "host": parsed.hostname,
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "port": str(parsed.port or 1025),
        "database": database,
        "extra": extras,
    }


def load_settings(
    *,
    uri: Optional[str] = None,
    env: Optional[Dict[str, str]] = None,
) -> Settings:
    """Build ``Settings`` from env / explicit overrides.

    Precedence:
      1. Explicit ``uri`` argument
      2. ``DATABASE_URI`` env var
      3. ``TERADATA_HOST`` + ``TERADATA_USER`` + ``TERADATA_PASSWORD``
    """
    env = env if env is not None else os.environ
    uri = uri or env.get("DATABASE_URI")
    if uri:
        p = _parse_uri(uri)
        return Settings(
            host=p["host"],
            user=p["user"],
            password=p["password"],
            database=p["database"],
            port=int(p["port"]),
            extra=p["extra"],
            bind_host=env.get("SC_BIND_HOST", "127.0.0.1"),
            bind_port=int(env.get("SC_BIND_PORT", "8080")),
            cors_allow_origins=env.get("SC_CORS_ORIGINS", "*"),
        )

    host = env.get("TERADATA_HOST")
    user = env.get("TERADATA_USER")
    password = env.get("TERADATA_PASSWORD")
    if not (host and user and password):
        raise RuntimeError(
            "No DATABASE_URI found and TERADATA_HOST/USER/PASSWORD are not all set. "
            "Example: DATABASE_URI=teradata://user:pass@host:1025/demo_user"
        )
    return Settings(
        host=host,
        user=user,
        password=password,
        database=env.get("TERADATA_DATABASE", "demo_user"),
        port=int(env.get("TERADATA_PORT", "1025")),
        bind_host=env.get("SC_BIND_HOST", "127.0.0.1"),
        bind_port=int(env.get("SC_BIND_PORT", "8080")),
        cors_allow_origins=env.get("SC_CORS_ORIGINS", "*"),
    )
