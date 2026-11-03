# Supabase setup

1. Open your Supabase project and go to **SQL Editor**.
2. Run the migration in `migrations/20261103000100_world_foundation.sql`.
3. Create your first user through Supabase Auth (email/password).
4. In SQL Editor, promote that account to the creator role:

```sql
update public.profiles
set role = 'creator', display_name = 'Etho'
where id = (
  select id from auth.users
  where email = 'YOUR_LOGIN_EMAIL'
);
```

5. Add the frontend environment variables to your deployment settings (and local `.env.local`):

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY
```

Use the project's publishable/anon key only in the browser. **Never** put the service-role key in frontend variables, GitHub, or client code.

The migration enables row-level security. A newly registered account is an observer until you promote it using the SQL above. Only the creator role can read or change civilization data.


## Migration 004 — geography, borders, and environmental events

After migrations 001–003 have succeeded, run the complete SQL file `migrations/20261103000400_geography_civilizations_environment.sql` in the Supabase SQL Editor. It creates persistent terrain features, the first civilization and its territory, and an environment tick that can create weather and natural-disaster events. Those events change shared resources and can generate prayers linked to the exact event.


## Migration 005 — autonomous civilization development

After migrations 001–004 have succeeded, run the complete SQL file `migrations/20261103000500_autonomous_civilization_development.sql` in the Supabase SQL Editor. It adds a persistent building registry and citizen work log, then introduces a once-per-simulated-year development tick. Adult citizens are assigned work such as foraging, water collection, timber and stone gathering, farming, and crafting. Their output changes shared food, water, and building-material reserves. The system constructs homes when shelter is insufficient, creates shared growing plots, and can found Riverstead when the population and material reserves meet the threshold. The observatory calls this function automatically during its normal refresh.
