"""PROJECT ETHO API foundation. The database-backed simulation engine is intentionally not enabled yet."""
from datetime import datetime, timezone
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="PROJECT ETHO API", version="0.1.0")
origins = os.getenv("FRONTEND_ORIGINS", "http://localhost:5173").split(",")
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

class WorldStatus(BaseModel):
    world_id: str
    world_name: str
    started_at: datetime
    real_time: datetime
    simulated_year: float
    time_ratio: str
    mode: str

# Temporary epoch anchor. Replace with a persisted world_settings row before enabling
# multi-user deployment or production offline progression.
WORLD_STARTED_AT = datetime.now(timezone.utc)

@app.get("/health")
def health():
    return {"status": "ok", "service": "project-etho-api"}

@app.get("/api/world/status", response_model=WorldStatus)
def world_status():
    now = datetime.now(timezone.utc)
    elapsed_hours = (now - WORLD_STARTED_AT).total_seconds() / 3600
    return WorldStatus(
        world_id="X-219B",
        world_name="The First World",
        started_at=WORLD_STARTED_AT,
        real_time=now,
        simulated_year=1 + elapsed_hours,
        time_ratio="1 real hour = 1 simulated year",
        mode="foundation-preview",
    )
