-- PROJECT ETHO: fix child identity consistency during the first family milestone.
-- The child UUID must be explicitly inserted into citizens before family links reference it.

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
  inserted_count integer := 0;
begin
  if not public.is_creator() then
    raise exception 'Creator permission required';
  end if;

  select id into wid from public.worlds where slug=p_slug;
  if wid is null then
    raise exception 'World not found';
  end if;

  -- Prevent the scheduled tick and browser refresh from creating the same milestone concurrently.
  perform pg_advisory_xact_lock(hashtext(wid::text), hashtext('early-family-growth'));

  select simulated_year into yr from public.get_world_status(p_slug);
  if yr < 2 then
    return jsonb_build_object('created',false,'reason','The first family milestone is approaching.');
  end if;

  select p.* into pair
  from public.citizen_partnerships p
  join public.citizens a on a.id=p.citizen_a_id
  join public.citizens b on b.id=p.citizen_b_id
  where p.world_id=wid
    and a.status='alive' and b.status='alive'
    and a.age_years between 20 and 45
    and b.age_years between 20 and 45
    and not exists (
      select 1 from public.citizens c
      where c.parent_a_id in (p.citizen_a_id,p.citizen_b_id)
         or c.parent_b_id in (p.citizen_a_id,p.citizen_b_id)
    )
  order by p.formed_year,p.created_at
  limit 1;

  if pair.id is null then
    return jsonb_build_object('created',false,'reason','Waiting for an established household.');
  end if;

  if exists (
    select 1 from public.world_events
    where world_id=wid and event_type='first_child'
  ) then
    return jsonb_build_object('created',false,'reason','The first family milestone is complete.');
  end if;

  child_id := gen_random_uuid();
  child_name := 'Asha';
  if exists(select 1 from public.citizens where world_id=wid and full_name=child_name) then
    child_name := 'Asha-'||floor(yr)::text;
  end if;

  -- Explicitly use child_id here; otherwise the table default generates a
  -- different ID and the subsequent family-link foreign keys fail.
  insert into public.citizens(
    id,world_id,settlement_id,full_name,age_years,birth_year,status,traits,
    personality,beliefs,ambitions,household_id,parent_a_id,parent_b_id,
    family_id,x,y,current_activity
  )
  select
    child_id,wid,a.settlement_id,child_name,0,yr,'alive',
    array['curious','observant'],
    '{"temperament":"developing"}'::jsonb,
    '{}'::jsonb,
    array['learn about the world'],
    pair.household_id,a.id,b.id,pair.household_id,
    (a.x+b.x)/2,(a.y+b.y)/2,'Being cared for by family'
  from public.citizens a
  join public.citizens b on b.id=pair.citizen_b_id
  where a.id=pair.citizen_a_id;

  get diagnostics inserted_count = row_count;
  if inserted_count <> 1 then
    raise exception 'Could not create the first child record (inserted % rows).', inserted_count;
  end if;

  insert into public.citizen_family_links(world_id,parent_id,child_id)
  values
    (wid,pair.citizen_a_id,child_id),
    (wid,pair.citizen_b_id,child_id);

  update public.citizens
  set household_id=pair.household_id,family_id=pair.household_id
  where id in (pair.citizen_a_id,pair.citizen_b_id);

  insert into public.world_events(world_id,world_year,event_type,title,description,metadata)
  values(
    wid,yr,'first_child','A new generation begins',
    child_name||' has joined the community. The household begins a new chapter of care and responsibility.',
    jsonb_build_object(
      'citizen_id',child_id,
      'parent_a_id',pair.citizen_a_id,
      'parent_b_id',pair.citizen_b_id
    )
  );

  insert into public.prayers(world_id,citizen_id,message,emotional_state,context,world_year,related_event_id)
  values(
    wid,pair.citizen_a_id,
    'A child has joined our family. We hope they will grow safely and find a place among our people.',
    'hopeful',
    'The first new generation has arrived in the growing community.',
    yr,
    (select id from public.world_events
     where world_id=wid and event_type='first_child'
     order by created_at desc limit 1)
  );

  update public.world_society_state
  set shelter_capacity=greatest(shelter_capacity,16),updated_at=now()
  where world_id=wid;

  return jsonb_build_object(
    'created',true,
    'child_id',child_id,
    'child_name',child_name,
    'world_year',yr,
    'births',1
  );
end;
$$;

grant execute on function public.advance_early_family_growth(text) to authenticated;
