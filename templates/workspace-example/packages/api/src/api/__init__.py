"""API library module."""

import httpx
from pydantic import BaseModel
from shared import models

class APIClient:
    def __init__(self, base_url: str):
        self.base_url = base_url
        self.client = httpx.AsyncClient()
        
    async def get_data(self):
        response = await self.client.get(f"{self.base_url}/data")
        return response.json()
