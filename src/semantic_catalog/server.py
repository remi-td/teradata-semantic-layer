"""FastAPI application factory.

Usage::

    from semantic_catalog.server import create_app
    app = create_app()

    # development
    uvicorn semantic_catalog.server:app --reload
"""
from __future__ import annotations

import logging
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import __version__
from .api.catalog import router as catalog_router
from .api.export import router as export_router
from .api.importer import router as import_router
from .api.query import router as query_router
from .auth import require_token
from .config import load_settings
from .mcp import router as mcp_router

log = logging.getLogger(__name__)

STATIC_DIR = Path(__file__).parent / "static"


def create_app() -> FastAPI:
    settings = load_settings()
    app = FastAPI(
        title="Teradata Semantic Catalog",
        description=(
            "Exploration, query-generation, import and export for the "
            "semantic catalog that lives inside Teradata Vantage."
        ),
        version=__version__,
    )
    origins = [o.strip() for o in settings.cors_allow_origins.split(",") if o.strip()] or ["*"]
    # CORS spec: `*` + credentials is illegal (browsers reject it). If the
    # operator left the default permissive value, drop credentials; the
    # localhost-only bind default keeps this safe for dev. Production
    # deployments should set SC_CORS_ORIGINS to an explicit allowlist.
    wildcard = "*" in origins
    if wildcard:
        log.warning(
            "CORS_ALLOW_ORIGINS contains '*' — disabling allow_credentials. "
            "Set SC_CORS_ORIGINS to an explicit comma-separated allowlist for production."
        )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=not wildcard,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # API routers — every /api/* endpoint shares the same bearer-token
    # dependency as /mcp/* (via .auth.require_token). When no token env
    # var is set, require_token is a no-op (localhost dev default).
    auth_dep = [Depends(require_token)]
    app.include_router(catalog_router, dependencies=auth_dep)
    app.include_router(query_router,   dependencies=auth_dep)
    app.include_router(import_router,  dependencies=auth_dep)
    app.include_router(export_router,  dependencies=auth_dep)
    app.include_router(mcp_router)

    # Health / info — `/api/health` stays public (liveness for load
    # balancers). `/api/ping` requires auth because it exercises the DB.
    @app.get("/api/health")
    def health():
        return {
            "status": "ok",
            "version": __version__,
            "host": settings.host,
            "database": settings.catalog_db,
        }

    @app.get("/api/ping", dependencies=auth_dep)
    def ping():
        """Cheap liveness probe — actually hits the database.

        Returns a sanitised error message on failure so the raw driver
        exception (which often includes the DATABASE_URI with its
        password) never reaches the caller. The full traceback goes to
        the server log only.
        """
        from .db import get_pool
        try:
            with get_pool().cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            return {"ok": True, "host": settings.host}
        except Exception as e:  # noqa: BLE001
            log.exception("ping failed")
            raise HTTPException(503, "database unreachable")

    # Static frontend.
    if STATIC_DIR.is_dir():
        app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

        @app.get("/", include_in_schema=False)
        def index():
            return FileResponse(str(STATIC_DIR / "index.html"))
    else:
        log.warning("static directory not found at %s — GUI disabled", STATIC_DIR)

    return app


# Importable top-level for ``uvicorn semantic_catalog.server:app``
app = create_app()
