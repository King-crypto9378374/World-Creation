-- PROJECT ETHO: generated geography, civilization borders, and event-driven environment
create table if not exists public.world_geography_features (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  name text not null,
  feature_type text not null check (feature_type in ('river','mountain_range','forest','lake','wetland','plains','coast','desert')),
  biome text not null default '',
  coordinates jsonb not null default '[]'::jsonb,
  description text not null default '',
  elevation numeric not null default 0,
  created_at timestamptz not null default now(),
  unique(world_id,name)
);
create table if not exists public.civilizations (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  name text not null,
  government_type text not null default 'tribal community',
  status text not null default 'forming',
  founded_year numeric not null default 1,
  population integer not null default 0,
  color text not null default '#d5b36b',
  capital_settlement_id uuid references public.settlements(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(world_id,name)
);
create table if not exists public.civilization_borders (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  civilization_id uuid not null references public.civilizations(id) on delete cascade,
  polygon jsonb not null,
  valid_from_year numeric not null default 1,
  is_current boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists geography_world_type_idx on public.world_geography_features(world_id,feature_type);
create index if not exists civilization_border_current_idx on public.civilization_borders(world_id,is_current);
alter table public.world_society_state add column if not exists last_environment_year integer not null default 1;
alter table public.world_geography_features enable row level security;
alter table public.civilizations enable row level security;
alter table public.civilization_borders enable row level security;
drop policy if exists "creator all geography" on public.world_geography_features;
create policy "creator all geography" on public.world_geography_features for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all civilizations" on public.civilizations;
create policy "creator all civilizations" on public.civilizations for all to authenticated using(public.is_creator()) with check(public.is_creator());
drop policy if exists "creator all civilization borders" on public.civilization_borders;
create policy "creator all civilization borders" on public.civilization_borders for all to authenticated using(public.is_creator()) with check(public.is_creator());

do $$
declare wid uuid; hearth uuid; civ uuid;
begin
  select id into wid from public.worlds where slug='x-219b';
  insert into public.world_geography_features(world_id,name,feature_type,biome,coordinates,description,elevation) values
    (wid,'The Silver River','river','river valley','[[0.08,0.38],[0.19,0.43],[0.29,0.40],[0.39,0.49],[0.48,0.52],[0.59,0.47],[0.70,0.55],[0.83,0.51],[0.94,0.59]]'::jsonb,'The main freshwater river system; settlements depend on its floodplain.',0),
    (wid,'The Northwind Range','mountain_range','alpine','[[0.17,0.13],[0.25,0.20],[0.34,0.12],[0.43,0.22],[0.52,0.14],[0.62,0.21],[0.72,0.13]]'::jsonb,'A high mountain chain that shapes rainfall and travel.',1800),
    (wid,'Oldgrowth Forest','forest','temperate woodland','[[0.12,0.28],[0.18,0.24],[0.24,0.29],[0.31,0.25],[0.36,0.32]]'::jsonb,'Dense woodland with timber, shelter, and wildlife.',240),
    (wid,'The Greenwood','forest','temperate woodland','[[0.63,0.67],[0.70,0.63],[0.77,0.70],[0.84,0.66]]'::jsonb,'A broad forest that provides timber and food but can carry wildfire.',190),
    (wid,'Mirror Lake','lake','freshwater','[[0.74,0.36],[0.78,0.34],[0.82,0.37],[0.80,0.42],[0.75,0.41]]'::jsonb,'A freshwater lake fed by mountain runoff.',90),
    (wid,'Southfen Marsh','wetland','marsh','[[0.24,0.73],[0.31,0.70],[0.38,0.75],[0.44,0.72]]'::jsonb,'A wetland rich in reeds, fish, and migratory birds.',8),
    (wid,'The Eastern Grasslands','plains','temperate grassland','[[0.57,0.46],[0.69,0.43],[0.80,0.49],[0.89,0.45]]'::jsonb,'Open grassland used by grazing animals and travelling groups.',120)
  on conflict(world_id,name) do nothing;

  select id into hearth from public.settlements where world_id=wid order by created_at limit 1;
  insert into public.civilizations(world_id,name,government_type,status,founded_year,population,capital_settlement_id)
  values(wid,'The First Hearth','kinship-based community','forming',1,12,hearth)
  on conflict(world_id,name) do nothing;
  select id into civ from public.civilizations where world_id=wid and name='The First Hearth';
  update public.civilizations set population=(select count(*) from public.citizens where world_id=wid and status='alive') where id=civ;
  if not exists(select 1 from public.civilization_borders where civilization_id=civ and is_current) then
    insert into public.civilization_borders(world_id,civilization_id,polygon,valid_from_year)
    values(wid,civ,'[[0.32,0.35],[0.53,0.31],[0.67,0.43],[0.64,0.62],[0.48,0.70],[0.30,0.57]]'::jsonb,1);
  end if;
end $$;

create or replace function public.advance_world_environment(p_slug text default 'x-219b')
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  whole_year integer;
  last_year integer;
  roll numeric;
  kind text;
  title_text text;
  description_text text;
  impact_food numeric := 0;
  impact_water numeric := 0;
  impact_stability numeric := 0;
  loc record;
  person record;
  affected_settlement uuid;
  event_id uuid;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  select simulated_year into yr from public.get_world_status(p_slug);
  whole_year:=floor(yr)::integer;
  insert into public.world_society_state(world_id) values(wid) on conflict(world_id) do nothing;
  select last_environment_year into last_year from public.world_society_state where world_id=wid for update;
  if whole_year<=last_year then return jsonb_build_object('created',false,'reason','year_already_processed'); end if;
  update public.world_society_state set last_environment_year=whole_year where world_id=wid;
  roll:=random();
  if roll>0.34 then return jsonb_build_object('created',false,'reason','quiet_year','world_year',whole_year); end if;

  select id,name,x,y,biome into loc from public.world_locations where world_id=wid order by random() limit 1;
  if loc.id is null then return jsonb_build_object('created',false,'reason','no_location'); end if;
  kind:=case
    when roll<0.055 then 'earthquake'
    when roll<0.115 then 'wildfire'
    when roll<0.18 then 'flood'
    when roll<0.235 then 'severe_storm'
    when roll<0.29 then 'drought'
    else 'heavy_rainfall' end;
  title_text:=case kind
    when 'earthquake' then 'The ground trembles'
    when 'wildfire' then 'A wildfire spreads'
    when 'flood' then 'Floodwaters rise'
    when 'severe_storm' then 'A severe storm crosses the land'
    when 'drought' then 'A dry season takes hold'
    else 'Heavy rainfall reaches the region' end;
  description_text:=case kind
    when 'earthquake' then 'An earthquake shakes the area around '||loc.name||'. People seek safer ground and inspect shelters and water sources.'
    when 'wildfire' then 'A wildfire threatens vegetation near '||loc.name||'. Smoke, lost forage, and disrupted travel affect nearby life.'
    when 'flood' then 'Floodwater spreads through low ground near '||loc.name||'. Paths and gathering areas become difficult to use.'
    when 'severe_storm' then 'Strong winds and heavy weather pass over '||loc.name||'. Travel slows and exposed shelters may be damaged.'
    when 'drought' then 'Rainfall has been scarce around '||loc.name||'. Water becomes harder to find and plants grow poorly.'
    else 'Heavy rainfall replenishes water near '||loc.name||', while low-lying paths become muddy and difficult to cross.' end;
  impact_food:=case kind when 'wildfire' then -8 when 'flood' then -5 when 'drought' then -7 when 'earthquake' then -3 else 0 end;
  impact_water:=case kind when 'drought' then -12 when 'wildfire' then -4 when 'heavy_rainfall' then 9 when 'flood' then 5 else 0 end;
  impact_stability:=case kind when 'earthquake' then -8 when 'wildfire' then -7 when 'flood' then -6 when 'severe_storm' then -4 when 'drought' then -5 else 1 end;
  select id into affected_settlement from public.settlements where world_id=wid order by power(x-loc.x,2)+power(y-loc.y,2) limit 1;

  insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
  values(wid,yr,kind,title_text,description_text,jsonb_build_object('location_id',loc.id,'location_name',loc.name,'x',loc.x,'y',loc.y,'biome',loc.biome,'severity',case when roll<0.115 then 'major' else 'moderate' end))
  returning id into event_id;
  update public.world_society_state set
    food=greatest(0,least(100,food+impact_food)),
    fresh_water=greatest(0,least(100,fresh_water+impact_water)),
    stability=greatest(0,least(100,stability+impact_stability)),
    updated_at=now()
  where world_id=wid;
  update public.citizens set
    current_activity=case when kind in ('earthquake','wildfire','flood','severe_storm') then 'Responding to '||lower(title_text) else 'Adapting to '||lower(title_text) end,
    needs=jsonb_set(coalesce(needs,'{}'::jsonb),'{safety}',to_jsonb(greatest(0,least(100,coalesce((needs->>'safety')::numeric,80)+impact_stability))))
  where world_id=wid and status='alive' and settlement_id=affected_settlement;
  select id,full_name into person from public.citizens where world_id=wid and status='alive' order by random() limit 1;
  if person.id is not null then
    insert into public.prayers(world_id,citizen_id,message,emotional_state,context,world_year,related_event_id)
    values(wid,person.id,
      case kind
        when 'earthquake' then 'The ground moved beneath us. Our people are frightened and we are checking the shelters. Please watch over everyone.'
        when 'wildfire' then 'Smoke is rising near our home and the familiar paths are changing. We need wisdom to keep our families safe.'
        when 'flood' then 'The water has risen over places we used every day. We are trying to find a safe way through.'
        when 'severe_storm' then 'The storm is stronger than we expected. We are sheltering together and hoping our homes hold.'
        when 'drought' then 'The land is dry and finding water takes longer. We are worried about what the next season will bring.'
        else 'The rain has returned to the valley. We are grateful, though the paths are difficult and the river is high.' end,
      case kind when 'heavy_rainfall' then 'grateful' when 'drought' then 'worried' else 'afraid' end,
      description_text||' This prayer was created because the event affected the shared world state.',yr,event_id);
  end if;
  return jsonb_build_object('created',true,'event_id',event_id,'event_type',kind,'location',loc.name,'world_year',yr);
end;
$$;
grant execute on function public.advance_world_environment(text) to authenticated;
