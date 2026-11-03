-- PROJECT ETHO: prevent repeated same-year border snapshots.
-- The culture engine runs on every dashboard refresh; only one border
-- snapshot per civilization per simulated year should remain current.

create or replace function public.keep_one_civilization_border_per_year()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  existing_border_id uuid;
begin
  select id into existing_border_id
  from public.civilization_borders
  where civilization_id=NEW.civilization_id
    and valid_from_year=NEW.valid_from_year
  order by id
  limit 1;

  if existing_border_id is not null then
    update public.civilization_borders
    set is_current=(id=existing_border_id)
    where civilization_id=NEW.civilization_id
      and valid_from_year=NEW.valid_from_year;
    return null;
  end if;

  return NEW;
end;
$$;

drop trigger if exists civilization_border_one_per_year
on public.civilization_borders;

create trigger civilization_border_one_per_year
before insert on public.civilization_borders
for each row
execute function public.keep_one_civilization_border_per_year();
