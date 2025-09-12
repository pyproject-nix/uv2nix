"""Shared utilities and models."""

from typing_extensions import TypedDict
from pydantic import BaseModel

class UserModel(BaseModel):
    id: int
    name: str
    email: str

class ConfigDict(TypedDict):
    debug: bool
    database_url: str
