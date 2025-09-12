"""Web application module."""

from fastapi import FastAPI
from shared import utils

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "Hello from webapp!"}
