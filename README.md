# PROJECT ETHO — World X-219B

A persistent, accelerated civilization simulation observed through the private creator console of **Etho**.

## Current build

- React + TypeScript + Vite creator observatory.
- Supabase Auth login and creator-role gate.
- PostgreSQL schema with row-level security for worlds, settlements, citizens, memories, prayers, responses, broadcasts, and events.
- Server-authoritative simulated clock: one real hour equals one simulated year.
- Opening world seed: one settlement, twelve citizens, and two recorded prayers.
- Persistent creator prayer responses and broadcast records.
- Live population, settlement, and prayer counts.

> Citizens and their emotions, memories, and experiences are fictional simulated data, not conscious beings or actual suffering.

## Supabase setup

Read [supabase/README.md](supabase/README.md), then run the migration in `supabase/migrations/` using the Supabase SQL Editor.

Set these frontend environment variables in your deployment platform and local `.env.local`:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY
```

Never expose a Supabase service-role key in frontend code.

## Run locally

```bash
npm install
npm run dev
```

The frontend uses Vite. The FastAPI service in `backend/` is a separate future simulation-worker foundation and is not required for the current Supabase-backed dashboard.

## Current limitations

- The initial citizen and prayer records are seeded once by the migration.
- Prayer responses and broadcasts persist, but citizens do not yet autonomously generate new prayers or receive broadcasts.
- Population counts are real database counts; birth, aging, death, relationships, culture, economy, and technology simulation are upcoming.
- The current clock derives from the persisted world start timestamp and database server time.

## Next milestones

1. Build the deterministic simulation tick and safe offline catch-up.
2. Generate citizen decisions, relationships, life events, and prayers from persistent state.
3. Make creator replies influence citizen memories, beliefs, and later decisions.
4. Add pause/resume and command console with server-side audit history.
5. Add civilization systems, settlements, and a Three.js globe.
6. Add selected AI-generated narrative events without using AI for every routine simulation action.
