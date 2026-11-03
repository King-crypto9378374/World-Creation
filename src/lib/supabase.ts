import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const isSupabaseConfigured = Boolean(url && anonKey && !url.includes('YOUR_PROJECT_REF') && !anonKey.includes('YOUR_SUPABASE'));
export const supabase = isSupabaseConfigured ? createClient(url!, anonKey!) : null;

export type WorldStatus = {
  id: string;
  slug: string;
  name: string;
  simulated_year: number;
  real_now: string;
  started_at: string;
  paused: boolean;
  time_ratio_seconds_per_year: number;
};

export type PrayerRecord = {
  id: string;
  message: string;
  emotional_state: string;
  context: string;
  world_year: number;
  created_at: string;
  status: string;
  related_event_id?: string | null;
  world_events?: { title: string; description: string; event_type: string } | null;
  citizens: { full_name: string; settlement_id: string | null; settlements: { name: string } | null } | null;
};

export async function loadWorldStatus() {
  if (!supabase) throw new Error('Supabase is not configured. Add the VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY environment variables.');
  const { data, error } = await supabase.rpc('get_world_status', { p_slug: 'x-219b' });
  if (error) throw error;
  return (data?.[0] ?? null) as WorldStatus | null;
}

export async function loadPrayers() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase
    .from('prayers')
    .select('id,message,emotional_state,context,world_year,created_at,status,related_event_id,world_events(title,description,event_type),citizens(full_name,settlement_id,settlements(name))')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as PrayerRecord[];
}

export async function answerPrayer(prayerId: string, creatorId: string, message: string) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { error: responseError } = await supabase.from('prayer_responses').insert({
    prayer_id: prayerId, creator_id: creatorId, message
  });
  if (responseError) throw responseError;
  const { error: prayerError } = await supabase.from('prayers').update({ status: 'answered' }).eq('id', prayerId);
  if (prayerError) throw prayerError;
}

export async function createBroadcast(creatorId: string, message: string, worldYear: number, worldId: string) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { error } = await supabase.from('broadcasts').insert({
    world_id: worldId, creator_id: creatorId, message, issued_at_year: worldYear
  });
  if (error) throw error;
}

export async function loadWorldCounts(worldId: string) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const [citizens, settlements] = await Promise.all([
    supabase.from('citizens').select('id', { count: 'exact', head: true }).eq('world_id', worldId).eq('status', 'alive'),
    supabase.from('settlements').select('id', { count: 'exact', head: true }).eq('world_id', worldId)
  ]);
  if (citizens.error) throw citizens.error;
  if (settlements.error) throw settlements.error;
  return { population: citizens.count ?? 0, settlements: settlements.count ?? 0 };
}
