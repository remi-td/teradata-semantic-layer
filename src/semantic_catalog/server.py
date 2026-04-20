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

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import __version__
from .api.catalog import router as catalog_router
from .api.export import router as export_router
from .api.importer import router as import_router
from .api.query import router as query_router
from .config import load_settings

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
    origins = [o.strip() for o in settings.cors_allow_origins.split(",") if o.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins or ["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # API routers
    app.include_router(catalog_router)
    app.include_router(query_router)
    app.include_router(import_router)
    app.include_router(export_router)

    # Health / info.
    @app.get("/api/health")
    def health():
        return {
            "status": "ok",
            "version": __version__,
            "host": settings.host,
            "database": settings.catalog_db,
        }

    @app.get("/api/ping")
    def ping():
        """Cheap liveness probe — actually hits the database."""
        from .db import get_pool
        try:
            with get_pool().cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            return {"ok": True, "host": settings.host}
        except Exception as e:
            raise HTTPException(503, f"database unreachable: {e}")

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
