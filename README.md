# PROJECT ETHO — World X-219B

A persistent, accelerated civilization simulation observed through the creator console of **Etho**.

## Current foundation

- React + TypeScript + Vite observatory dashboard.
- Dual-clock concept: one real hour represents one simulated year.
- Creator console visual system and responsive layout.
- Prayer inbox and citizen-response interface (currently preview data only).
- Broadcast composer (currently preview-only).
- FastAPI service foundation with a world-status endpoint.

> **Important:** This is a simulation project. Citizens, their memories, emotions, and experiences are fictional computational representations; the software does not create conscious beings or actual suffering.

## Run locally

### Frontend
```bash
npm install
npm run dev
```

### Backend
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn backend.main:app --reload --port 8000
```

API health: `GET /health`  
World status: `GET /api/world/status`

## Next implementation milestones

1. Persist world settings, clock anchor, and simulation events in PostgreSQL.
2. Add authentication and enforce creator-only administrative actions server-side.
3. Create citizen, household, settlement, relationship, memory, and event schemas.
4. Implement deterministic hourly/yearly simulation ticks and safe offline catch-up.
5. Build persistent prayer delivery, creator replies, and citizen belief/memory updates.
6. Add broadcasts with technology-aware reach and delayed interpretation.
7. Add civilization systems and an interactive Three.js globe.

## Architecture principles

- Server time is authoritative; browser clocks are display-only.
- Persist simulation state and event history; never rely on an open browser tab.
- Use deterministic rules for routine life and reserve AI calls for selected high-impact narrative events.
- Validate every creator command on the backend and log all world-changing actions.
- Keep secrets in environment variables; never commit API keys.
