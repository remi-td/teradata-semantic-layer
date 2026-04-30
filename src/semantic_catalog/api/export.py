"""Export endpoints — thin wrappers over ``semantic_catalog.services``."""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Response

from .. import services

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/export", tags=["export"])


@router.get("/osi/{model_name}", response_class=Response)
def export_osi(model_name: str) -> Response:
    """Projection to OSI 0.1.x YAML."""
    try:
        text = services.export_osi_for_model(model_name=model_name)
    except services.EntityNotFound as e:
        raise HTTPException(404, str(e))
    return Response(content=text, media_type="text/yaml")
