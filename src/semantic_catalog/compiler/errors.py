"""Typed compile errors.

The API layer converts these into 4xx responses with a stable error code
so that MCP tools and the GUI can surface targeted guidance (e.g. "pin a
role" for AMBIGUOUS_PATH).
"""
from __future__ import annotations

from typing import List, Optional


class CompileError(Exception):
    """Base class. ``code`` is a short, stable machine-readable tag."""
    code: str = "COMPILE_ERROR"

    def __init__(self, message: str, *, details: Optional[dict] = None):
        super().__init__(message)
        self.message = message
        self.details = details or {}

    def to_dict(self) -> dict:
        return {"code": self.code, "message": self.message, **self.details}


class UnknownModelError(CompileError):
    code = "UNKNOWN_MODEL"


class UnknownEntityError(CompileError):
    """Dim, metric, or filter references a name that doesn't exist in the model."""
    code = "UNKNOWN_ENTITY"


class AmbiguousPathError(CompileError):
    """Dim/filter references a dataset reachable via more than one role edge
    and the caller didn't pin a role."""
    code = "AMBIGUOUS_PATH"

    def __init__(self, message: str, *, roles: List[str],
                 details: Optional[dict] = None):
        merged = {"roles": list(roles), **(details or {})}
        super().__init__(message, details=merged)
        self.roles = list(roles)


class ChasmTrapError(CompileError):
    """Requested metrics span more grains than the compiler supports."""
    code = "CHASM_TRAP"


class CycleError(CompileError):
    """Metric-in-metric reference forms a cycle."""
    code = "CYCLE"

    def __init__(self, message: str, *, chain: List[str]):
        super().__init__(message, details={"chain": list(chain)})
        self.chain = list(chain)


class UnresolvedJoinError(CompileError):
    """BFS couldn't connect one or more required datasets to the anchor."""
    code = "UNRESOLVED_JOIN"

    def __init__(self, message: str, *, missing: List[str]):
        super().__init__(message, details={"missing": list(missing)})
        self.missing = list(missing)
