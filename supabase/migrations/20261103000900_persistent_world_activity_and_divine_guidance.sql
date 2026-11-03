-- PROJECT ETHO: persistent background ticks, visible journeys, early family growth,
-- an early second settlement, and consequential creator responses.
-- Apply after 20261103000800_civilization_knowledge_discoveries.sql.

-- Supabase's pg_cron keeps the world moving even when the observatory is closed.
create extension if not exists pg_cron;

create or replace function public.advance_citizen_movement(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  person record;
  origin_id uuid;
  destination record;
  started integer := 0;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  select simulated_year into yr from public.get_world_status(p_slug);

  -- A small rotating group begins a journey roughly every fifteen simulated minutes.
  for person in
    select c.id,c.x,c.y
    from public.citizens c
    where c.world_id=wid and c.status='alive' and c.age_years>=16
      and c.last_journey_year<=yr-0.25
      and not exists(select 1 from public.citizen_journeys j
        where j.citizen_id=c.id and j.status='travelling')
    order by md5(c.id::text||floor(yr*4)::text)
    limit 2
  loop
    select l.id into origin_id
    from public.world_locations l
    where l.world_id=wid
    order by power(l.x-person.x,2)+power(l.y-person.y,2)
    limit 1;

    select l.id,l.name into destination
    from public.world_locations l
    where l.world_id=wid and l.id<>origin_id
    order by md5(l.id::text||person.id::text||floor(yr*4)::text)
    limit 1;

    if origin_id is not null and destination.id is not null then
      insert into public.citizen_journeys(
        world_id,citizen_id,origin_location_id,destination_location_id,
        started_year,expected_arrival_year,purpose
      ) values(
        wid,person.id,origin_id,destination.id,yr,
        yr+(0.12+(mod(abs(hashtext(person.id::text)),8)::numeric/100)),
        'exploration and gathering'
      );
      update public.citizens
      set last_journey_year=yr,current_activity='Preparing to travel toward '||destination.name
      where id=person.id;
      started:=started+1;
    end if;
  end loop;

  return jsonb_build_object('world_year',yr,'journeys_started',started);
end;
$$;

grant execute on function public.advance_citizen_movement(text) to authenticated;

-- The first family event happens by simulated year 2, rather than waiting
-- for the original four-year cycle. Later births remain on the original cycle.
create or replace function public.advance_early_family_growth(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  pair record;
  child_id uuid;
  child_name text;
  birth_count integer := 0;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  select simulated_year into yr from public.get_world_status(p_slug);
  if yr<2 then return jsonb_build_object('created',false,'reason','The first family milestone is approaching.'); end if;

  select p.* into pair
  from public.citizen_partnerships p
  join public.citizens a on a.id=p.citizen_a_id
  join public.citizens b on b.id=p.citizen_b_id
  where p.world_id=wid and a.status='alive' and b.status='alive'
    and a.age_years between 20 and 45 and b.age_years between 20 and 45
    and not exists(select 1 from public.citizens c
      where c.parent_a_id in (p.citizen_a_id,p.citizen_b_id)
         or c.parent_b_id in (p.citizen_a_id,p.citizen_b_id))
  order by p.formed_year,p.created_at
  limit 1;

  if pair.id is null then
    return jsonb_build_object('created',false,'reason','Waiting for an established household.');
  end if;

  -- This early milestone is one-time; the regular engine handles later cycles.
  if exists(select 1 from public.world_events where world_id=wid and event_type='first_child') then
    return jsonb_build_object('created',false,'reason','The first family milestone is complete.');
  end if;

  child_id:=gen_random_uuid();
  child_name:='Asha';
  if exists(select 1 from public.citizens where world_id=wid and full_name=child_name) then
    child_name:='Asha-'||floor(yr)::text;
  end if;

  insert into public.citizens(
    world_id,settlement_id,full_name,age_years,birth_year,status,traits,
    personality,beliefs,ambitions,household_id,parent_a_id,parent_b_id,
    family_id,x,y,current_activity
  )
  select wid,a.settlement_id,child_name,0,yr,'alive',
    array['curious','observant'],
    '{"temperament":"developing"}'::jsonb,
    '{}'::jsonb,
    array['learn about the world'],
    pair.household_id,a.id,b.id,pair.household_id,
    (a.x+b.x)/2,(a.y+b.y)/2,'Being cared for by family'
  from public.citizens a
  join public.citizens b on b.id=pair.citizen_b_id
  where a.id=pair.citizen_a_id;

  insert into public.citizen_family_links(world_id,parent_id,child_id)
  values(wid,pair.citizen_a_id,child_id),(wid,pair.citizen_b_id,child_id);

  update public.citizens
  set household_id=pair.household_id,family_id=pair.household_id
  where id in(pair.citizen_a_id,pair.citizen_b_id);

  insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
  values(wid,yr,'first_child','A new generation begins',
    child_name||' has joined the community. The household begins a new chapter of care and responsibility.',
    jsonb_build_object('citizen_id',child_id,'parent_a_id',pair.citizen_a_id,'parent_b_id',pair.citizen_b_id));

  insert into public.prayers(world_id,citizen_id,message,emotional_state,context,world_year,related_event_id)
  values(wid,pair.citizen_a_id,
    'A child has joined our family. We hope they will grow safely and find a place among our people.',
    'hopeful','The first new generation has arrived in the growing community.',yr,
    (select id from public.world_events where world_id=wid and event_type='first_child' order by created_at desc limit 1));

  update public.world_society_state
  set shelter_capacity=greatest(shelter_capacity,16),updated_at=now()
  where world_id=wid;

  birth_count:=1;
  return jsonb_build_object('created',true,'child_id',child_id,'child_name',child_name,'world_year',yr,'births',birth_count);
end;
$$;

grant execute on function public.advance_early_family_growth(text) to authenticated;

-- Establish Riverstead earlier once the first community has enough supplies.
create or replace function public.advance_early_settlement(p_slug text default 'x-219b')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  wid uuid;
  yr numeric;
  base_settlement record;
  new_settlement_id uuid;
  moved integer := 0;
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  select id into wid from public.worlds where slug=p_slug;
  if wid is null then raise exception 'World not found'; end if;
  select simulated_year into yr from public.get_world_status(p_slug);
  if yr<2 then return jsonb_build_object('founded',false,'reason','The community is still preparing.'); end if;
  if (select count(*) from public.settlements where world_id=wid and status='active')>1 then
    return jsonb_build_object('founded',false,'reason','A second settlement already exists.');
  end if;
  if (select count(*) from public.citizens where world_id=wid and status='alive')<8
     or (select building_materials from public.world_society_state where world_id=wid)<12 then
    return jsonb_build_object('founded',false,'reason','The community needs more people and supplies.');
  end if;

  select * into base_settlement from public.settlements
  where world_id=wid and status='active'
  order by founded_year,created_at limit 1;
  if base_settlement.id is null then return jsonb_build_object('founded',false,'reason','No founding settlement exists.'); end if;

  insert into public.settlements(world_id,name,description,founded_year,population,biome,x,y,status)
  values(wid,'Riverstead',
    'A daughter settlement founded by a small group seeking new ground, fresh resources, and room to grow.',
    yr,0,base_settlement.biome,
    greatest(.08,least(.92,base_settlement.x+.19)),
    greatest(.08,least(.92,base_settlement.y+.13)),'active')
  returning id into new_settlement_id;

  update public.citizens c
  set settlement_id=new_settlement_id,
      x=greatest(.08,least(.92,base_settlement.x+.19)),
      y=greatest(.08,least(.92,base_settlement.y+.13)),
      current_activity='Founding Riverstead'
  where c.id in (
    select id from public.citizens
    where world_id=wid and status='alive' and age_years>=18
      and settlement_id=base_settlement.id
    order by md5(id::text||':early-riverstead') limit 2
  );
  get diagnostics moved=row_count;

  update public.settlements set population=moved where id=new_settlement_id;
  insert into public.world_locations(world_id,settlement_id,name,location_type,biome,x,y,description)
  values(wid,new_settlement_id,'Riverstead','settlement',base_settlement.biome,
    greatest(.08,least(.92,base_settlement.x+.19)),
    greatest(.08,least(.92,base_settlement.y+.13)),
    'A new village founded by citizens carrying tools and supplies into nearby land.')
  on conflict(world_id,name) do nothing;

  insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
  values(wid,yr,'settlement_founded','Riverstead is founded',
    'A small group has left the First Hearth and established a second settlement. A new community now grows beyond the original river valley camp.',
    jsonb_build_object('settlement_id',new_settlement_id,'founders',moved));

  update public.world_society_state
  set building_materials=greatest(0,building_materials-12),updated_at=now()
  where world_id=wid;

  return jsonb_build_object('founded',true,'settlement_id',new_settlement_id,'founders',moved,'world_year',yr);
end;
$$;

grant execute on function public.advance_early_settlement(text) to authenticated;

-- A creator response is recorded as a memory and changes the citizen's state.
-- Keyword guidance also affects the shared resources in a bounded, explicit way.
create or replace function public.respond_to_prayer(p_prayer_id uuid,p_message text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  prayer_row record;
  response_id uuid;
  event_id uuid;
  message_lower text;
  resource_effect text := 'comfort';
begin
  if not public.is_creator() then raise exception 'Creator permission required'; end if;
  if length(trim(coalesce(p_message,'')))<1 then raise exception 'A response message is required'; end if;

  select p.*,c.full_name into prayer_row
  from public.prayers p
  join public.citizens c on c.id=p.citizen_id
  where p.id=p_prayer_id
  for update of p;

  if prayer_row.id is null then raise exception 'Prayer not found'; end if;
  if prayer_row.status='answered' then raise exception 'This prayer has already been answered'; end if;

  insert into public.prayer_responses(prayer_id,creator_id,message)
  values(p_prayer_id,auth.uid(),trim(p_message))
  returning id into response_id;

  update public.prayers set status='answered' where id=p_prayer_id;

  message_lower:=lower(p_message);
  if message_lower ~ '(water|river|rain|well|spring)' then
    resource_effect:='water';
    update public.world_society_state set fresh_water=least(500,fresh_water+12),stability=least(100,stability+2),updated_at=now()
    where world_id=prayer_row.world_id;
  elsif message_lower ~ '(food|harvest|plant|seed|field|forage)' then
    resource_effect:='food';
    update public.world_society_state set food=least(500,food+12),stability=least(100,stability+2),updated_at=now()
    where world_id=prayer_row.world_id;
  elsif message_lower ~ '(protect|safe|shelter|courage|brave)' then
    resource_effect:='protection';
    update public.world_society_state set stability=least(100,stability+8),updated_at=now()
    where world_id=prayer_row.world_id;
  else
    update public.world_society_state set stability=least(100,stability+3),updated_at=now()
    where world_id=prayer_row.world_id;
  end if;

  update public.citizens
  set needs=jsonb_set(
        jsonb_set(coalesce(needs,'{}'::jsonb),'{belonging}',
          to_jsonb(least(100,greatest(0,coalesce((needs->>'belonging')::numeric,70)+18))),true),
        '{safety}',to_jsonb(least(100,greatest(0,coalesce((needs->>'safety')::numeric,70)+5))),true),
      beliefs=coalesce(beliefs,'{}'::jsonb)||jsonb_build_object('received_guidance',trim(p_message)),
      current_activity='Reflecting on a message from Etho'
  where id=prayer_row.citizen_id;

  insert into public.citizen_memories(citizen_id,world_year,memory_type,content,emotional_weight)
  values(prayer_row.citizen_id,prayer_row.world_year,'divine_response',
    'Etho answered: '||trim(p_message)||' The response brought comfort and changed the community''s circumstances ('||resource_effect||').',0.8);

  insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
  values(prayer_row.world_id,prayer_row.world_year,'divine_response',
    'A prayer receives an answer',
    prayer_row.full_name||' received a response from Etho. The message was remembered and influenced the community.',
    jsonb_build_object('citizen_id',prayer_row.citizen_id,'prayer_id',p_prayer_id,'response_id',response_id,'effect',resource_effect,'message',trim(p_message)))
  returning id into event_id;

  return jsonb_build_object('saved',true,'response_id',response_id,'event_id',event_id,'effect',resource_effect);
end;
$$;

grant execute on function public.respond_to_prayer(uuid,text) to authenticated;

-- Cron runs as the database owner. Set the creator's identity for the existing
-- creator-guarded simulation functions, then run every engine in one transaction.
create or replace function public.run_world_tick()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  creator_id uuid;
  sim_result jsonb;
  move_result jsonb;
  family_result jsonb;
  settlement_result jsonb;
  environment_result jsonb;
  development_result jsonb;
  culture_result jsonb;
  knowledge_result jsonb;
begin
  select id into creator_id from public.profiles where role='creator' order by created_at limit 1;
  if creator_id is null then raise exception 'No creator profile is configured'; end if;

  perform set_config('request.jwt.claim.sub',creator_id::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',creator_id,'role','authenticated')::text,true);

  sim_result:=public.advance_world_simulation('x-219b');
  move_result:=public.advance_citizen_movement('x-219b');
  family_result:=public.advance_early_family_growth('x-219b');
  settlement_result:=public.advance_early_settlement('x-219b');
  environment_result:=public.advance_world_environment('x-219b');
  development_result:=public.advance_civilization_development('x-219b');
  culture_result:=public.advance_civilization_culture('x-219b');
  knowledge_result:=public.advance_civilization_knowledge('x-219b');

  return jsonb_build_object(
    'simulation',sim_result,'movement',move_result,'family',family_result,
    'settlement',settlement_result,'environment',environment_result,
    'development',development_result,'culture',culture_result,'knowledge',knowledge_result
  );
end;
$$;

revoke all on function public.run_world_tick() from public,anon,authenticated;
grant execute on function public.run_world_tick() to postgres;

do $$
declare existing_job bigint;
begin
  if exists(select 1 from cron.job where jobname='world-x219b-autonomous-tick') then
    select jobid into existing_job from cron.job where jobname='world-x219b-autonomous-tick' limit 1;
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'world-x219b-autonomous-tick',
    '* * * * *',
    'select public.run_world_tick();'
  );
end;
$$;
