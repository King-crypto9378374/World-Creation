-- Inkweaver: cloud-backed, owner-isolated writing projects.
create table if not exists public.inkweaver_projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Untitled Project',
  subtitle text not null default '',
  genre text not null default '',
  content jsonb not null default jsonb_build_object(
    'characters', '[]'::jsonb,
    'chapters', '[]'::jsonb,
    'timeline', '[]'::jsonb,
    'plotThreads', '[]'::jsonb,
    'sceneCards', '[]'::jsonb,
    'loreNotes', '[]'::jsonb,
    'research', '[]'::jsonb,
    'inspiration', '[]'::jsonb,
    'dialogue', '[]'::jsonb,
    'worlds', '[]'::jsonb,
    'aiMessages', '[]'::jsonb
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists inkweaver_projects_owner_updated_idx
  on public.inkweaver_projects(owner_id, updated_at desc);

create or replace function public.set_inkweaver_project_updated_at()
returns trigger language plpgsql set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists inkweaver_projects_updated_at on public.inkweaver_projects;
create trigger inkweaver_projects_updated_at
before update on public.inkweaver_projects
for each row execute procedure public.set_inkweaver_project_updated_at();

alter table public.inkweaver_projects enable row level security;

drop policy if exists "Users can view their own Inkweaver projects" on public.inkweaver_projects;
create policy "Users can view their own Inkweaver projects"
  on public.inkweaver_projects for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists "Users can create their own Inkweaver projects" on public.inkweaver_projects;
create policy "Users can create their own Inkweaver projects"
  on public.inkweaver_projects for insert to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists "Users can update their own Inkweaver projects" on public.inkweaver_projects;
create policy "Users can update their own Inkweaver projects"
  on public.inkweaver_projects for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists "Users can delete their own Inkweaver projects" on public.inkweaver_projects;
create policy "Users can delete their own Inkweaver projects"
  on public.inkweaver_projects for delete to authenticated
  using (owner_id = (select auth.uid()));

grant select, insert, update, delete on public.inkweaver_projects to authenticated;
