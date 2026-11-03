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
