"""Export endpoints — thin wrappers over ``semantic_catalog.exporter``."""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Response

from ..db import get_pool
from ..exporter import export_osi_yaml

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/export", tags=["export"])


def _db_name() -> str:
    from ..config import load_settings
    return load_settings().catalog_db


@router.get("/osi/{model_name}", response_class=Response)
def export_osi(model_name: str) -> Response:
    """Projection to OSI 0.1.x YAML."""
    db = _db_name()
    with get_pool().cursor() as cur:
        text = export_osi_yaml(cur, db, model_name)
    if text is None:
        raise HTTPException(404, f"Unknown model: {model_name}")
    return Response(content=text, media_type="text/yaml")
