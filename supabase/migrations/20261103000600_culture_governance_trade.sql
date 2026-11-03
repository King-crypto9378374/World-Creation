-- PROJECT ETHO: culture, governance, trade, and organic territory growth.
-- Apply after 20261103000500_autonomous_civilization_development.sql.

create table if not exists public.civilization_culture (
  id uuid primary key default gen_random_uuid(),
  civilization_id uuid not null unique references public.civilizations(id) on delete cascade,
  language_name text not null default 'First Hearth Speech',
  cultural_identity text not null default 'The Hearthfolk',
  traditions jsonb not null default '["shared meals","oral storytelling","seasonal gathering"]'::jsonb,
  values jsonb not null default '["kinship","cooperation","curiosity"]'::jsonb,
  last_culture_year integer not null default 1,
  updated_at timestamptz not null default now()
);

create table if not exists public.trade_routes (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  civilization_id uuid not null references public.civilizations(id) on delete cascade,
  settlement_a_id uuid not null references public.settlements(id) on delete cascade,
  settlement_b_id uuid not null references public.settlements(id) on delete cascade,
  route_name text not null,
  status text not null default 'active' check(status in ('active','inactive')),
  established_year numeric not null,
  last_trade_year integer not null default 0,
  created_at timestamptz not null default now(),
  check(settlement_a_id <> settlement_b_id),
  unique(settlement_a_id,settlement_b_id)
);

create table if not exists public.trade_records (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  trade_route_id uuid not null references public.trade_routes(id) on delete cascade,
  world_year numeric not null,
  goods_sent jsonb not null default '{}'::jsonb,
  goods_received jsonb not null default '{}'::jsonb,
  summary text not null,
  created_at timestamptz not null default now()
);

alter table public.civilization_culture enable row level security;
alter table public.trade_routes enable row level security;
alter table public.trade_records enable row level security;

drop policy if exists "creator all civilization culture" on public.civilization_culture;
create policy "creator all civilization culture" on public.civilization_culture
  for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all trade routes" on public.trade_routes;
create policy "creator all trade routes" on public.trade_routes
  for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all trade records" on public.trade_records;
create policy "creator all trade records" on public.trade_records
  for all to authenticated using(public.is_creator()) with check(public.is_creator());

create or replace function public.advance_civilization_culture(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  yr_int integer;
  civ record;
  culture record;
  settlement_a record;
  settlement_b record;
  route record;
  pop integer;
  old_government text;
  new_government text;
  changed boolean := false;
  route_created integer := 0;
  trade_count integer := 0;
  boundary_radius numeric;
  center_x numeric;
  center_y numeric;
  polygon_json jsonb;
  event_id uuid;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  perform pg_advisory_xact_lock(hashtext(wid::text));
  select simulated_year into yr from public.get_world_status(p_slug);
  yr_int := floor(yr)::integer;

  select * into civ from public.civilizations
  where world_id=wid order by founded_year,created_at limit 1;
  if civ.id is null then
    return jsonb_build_object('advanced',false,'reason','No civilization exists yet.');
  end if;

  select count(*) into pop from public.citizens where world_id=wid and status='alive';
  insert into public.civilization_culture(civilization_id)
  values(civ.id) on conflict(civilization_id) do nothing;
  select * into culture from public.civilization_culture where civilization_id=civ.id for update;

  old_government := civ.government_type;
  new_government := case
    when pop < 20 then 'kinship-based community'
    when pop < 60 then 'council of elders'
    when pop < 150 then 'settlement council'
    when pop < 500 then 'chiefdom with local councils'
    else 'regional confederation'
  end;
  if old_government is distinct from new_government then
    update public.civilizations set government_type=new_government,population=pop where id=civ.id;
    insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
    values(wid,yr,'government_changed','A new form of leadership takes shape',
      'As the population grows, the community changes how it makes shared decisions. Its developing system is now described as a '||new_government||'.',
      jsonb_build_object('civilization_id',civ.id,'government',new_government,'population',pop));
    changed := true;
  else
    update public.civilizations set population=pop where id=civ.id;
  end if;

  -- Culture develops in five-year steps, retaining earlier customs while adding new ones.
  if yr_int >= culture.last_culture_year + 5 then
    update public.civilization_culture
    set language_name=case when yr_int>=31 then 'Old Hearth Tongue' when yr_int>=16 then 'Hearth Valley Speech' else language_name end,
        cultural_identity=case when yr_int>=31 then 'The River Valley People' when yr_int>=16 then 'The Hearth Valley Folk' else cultural_identity end,
        traditions=case
          when yr_int>=31 then traditions || '["river festival","shared market days"]'::jsonb
          when yr_int>=16 then traditions || '["planting season gathering","craft teaching circles"]'::jsonb
          else traditions || '["annual remembrance gathering"]'::jsonb end,
        last_culture_year=yr_int,updated_at=now()
    where civilization_id=civ.id;
    insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
    values(wid,yr,'culture_evolved','A shared culture takes deeper root',
      'Stories, customs, and everyday speech are being passed between generations and settlements. The community now identifies as '||
      (select cultural_identity from public.civilization_culture where civilization_id=civ.id)||'.',
      jsonb_build_object('civilization_id',civ.id,'language',(select language_name from public.civilization_culture where civilization_id=civ.id)));
    changed := true;
  end if;

  -- Establish a permanent route once two active settlements exist.
  select * into settlement_a from public.settlements
  where world_id=wid and status='active' order by founded_year,created_at limit 1;
  select * into settlement_b from public.settlements
  where world_id=wid and status='active' and id<>settlement_a.id
  order by founded_year,created_at limit 1;

  if settlement_a.id is not null and settlement_b.id is not null then
    insert into public.trade_routes(world_id,civilization_id,settlement_a_id,settlement_b_id,route_name,established_year)
    values(wid,civ.id,settlement_a.id,settlement_b.id,
      settlement_a.name||' — '||settlement_b.name||' trade path',yr)
    on conflict(settlement_a_id,settlement_b_id) do nothing;
    get diagnostics route_created=row_count;
  end if;

  -- A trade route exchanges stored resources once each simulated year.
  for route in
    select tr.*,sa.name as a_name,sb.name as b_name
    from public.trade_routes tr
    join public.settlements sa on sa.id=tr.settlement_a_id
    join public.settlements sb on sb.id=tr.settlement_b_id
    where tr.world_id=wid and tr.status='active' and tr.last_trade_year<yr_int
    order by tr.created_at
  loop
    update public.world_society_state
    set food=least(500,food+1.5),building_materials=least(500,building_materials+0.8),
        stability=least(100,stability+0.5),updated_at=now()
    where world_id=wid;
    insert into public.trade_records(world_id,trade_route_id,world_year,goods_sent,goods_received,summary)
    values(wid,route.id,yr,
      jsonb_build_object('food',1.5),
      jsonb_build_object('building_materials',0.8),
      route.a_name||' and '||route.b_name||' exchanged food, tools, and building materials.');
    update public.trade_routes set last_trade_year=yr_int where id=route.id;
    trade_count:=trade_count+1;
  end loop;

  -- Expand the current civilization border to include every active settlement.
  -- This is a simplified territorial envelope, not a surveyed geographic boundary.
  select avg(x),avg(y) into center_x,center_y
  from public.settlements where world_id=wid and status='active';
  if center_x is not null then
    select greatest(0.07,coalesce(max(sqrt(power(s.x-center_x,2)+power(s.y-center_y,2))),0)+0.07)
    into boundary_radius
    from public.settlements s where s.world_id=wid and s.status='active';
    select jsonb_agg(jsonb_build_array(
      round(greatest(0.02,least(0.98,center_x+cos(n*0.78539816339)*boundary_radius))::numeric,5),
      round(greatest(0.02,least(0.98,center_y+sin(n*0.78539816339)*boundary_radius))::numeric,5)
    ) order by n)
    into polygon_json from generate_series(0,7) as n;

    update public.civilization_borders set is_current=false
    where civilization_id=civ.id and is_current;
    insert into public.civilization_borders(world_id,civilization_id,polygon,valid_from_year,is_current)
    values(wid,civ.id,polygon_json,yr,true);
  end if;

  return jsonb_build_object('advanced',true,'world_year',yr,'population',pop,
    'government',new_government,'culture_changed',changed,
    'trade_routes_created',route_created,'trades_recorded',trade_count);
end;
$$;

grant execute on function public.advance_civilization_culture(text) to authenticated;
