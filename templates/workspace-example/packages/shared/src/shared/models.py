"""Shared data models."""

from pydantic import BaseModel
from typing_extensions import Optional

class BaseResponse(BaseModel):
    """Base response model."""
    success: bool
    message: Optional[str] = None
