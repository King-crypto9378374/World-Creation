# Inkweaver cloud setup

## One-time database setup
1. Open the Supabase project connected to this repository.
2. Open **SQL Editor**.
3. Run `supabase/migrations/20261103001100_inkweaver_projects.sql`.
4. In **Authentication → URL Configuration**, set the Site URL to your GitHub Pages URL:
   `https://king-crypto9378374.github.io/World-Creation/`
5. Add that same URL to the allowed Redirect URLs.

Inkweaver projects are stored in `public.inkweaver_projects`. Row-level security restricts each signed-in user to their own projects. Each project stores independent characters, chapters, timeline, plot threads, scene cards, lore, research, inspiration, dialogue, worlds, and AI chat history.

## Enable AI responses
1. In Supabase, open **Edge Functions → Secrets**.
2. Add `OPENAI_API_KEY` with your own OpenAI API key. The key is stored only in Supabase and is never exposed to the browser.
3. In GitHub repository **Settings → Secrets and variables → Actions → Secrets**, add:
   - `SUPABASE_ACCESS_TOKEN`: a Supabase personal access token
   - `SUPABASE_PROJECT_REF`: the project reference from the Supabase project URL
4. The GitHub Action deploys `inkweaver-companion` whenever its source changes. You can also run it manually from **Actions → Deploy Inkweaver AI → Run workflow**.

Optional Supabase Function Secret:
- `OPENAI_MODEL`: defaults to `gpt-4.1-mini`
- `INKWEAVER_ALLOWED_ORIGIN`: set to `https://king-crypto9378374.github.io` to restrict browser origins

The Edge Function verifies the signed-in user and confirms that the requested project belongs to them before sending project context to the AI provider.
