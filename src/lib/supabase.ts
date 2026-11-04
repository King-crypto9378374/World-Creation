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

export async function answerPrayer(prayerId: string, _creatorId: string, message: string) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.rpc('respond_to_prayer', {
    p_prayer_id: prayerId,
    p_message: message
  });
  if (error) throw error;
  if (!data?.saved) throw new Error('The response was not applied to the world.');
  return data;
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

export type InkweaverProject = {
  id: string;
  owner_id: string;
  title: string;
  subtitle: string;
  genre: string;
  content: Record<string, any>;
  created_at: string;
  updated_at: string;
};

export async function listInkweaverProjects() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('inkweaver_projects')
    .select('*').order('updated_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as InkweaverProject[];
}

export async function createInkweaverProject(ownerId: string, title = 'Untitled Project') {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('inkweaver_projects')
    .insert({ owner_id: ownerId, title, content: emptyInkweaverContent() })
    .select('*').single();
  if (error) throw error;
  return data as InkweaverProject;
}

export async function saveInkweaverProject(id: string, patch: Partial<InkweaverProject>) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.from('inkweaver_projects')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('id', id).select('*').single();
  if (error) throw error;
  return data as InkweaverProject;
}

export async function deleteInkweaverProject(id: string) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { error } = await supabase.from('inkweaver_projects').delete().eq('id', id);
  if (error) throw error;
}

export function emptyInkweaverContent() {
  return {
    characters: [], chapters: [], timeline: [], plotThreads: [], sceneCards: [],
    loreNotes: [], research: [], inspiration: [], dialogue: [], worlds: [], aiMessages: []
  };
}

export async function askInkweaver(projectId: string, messages: { role: 'user' | 'assistant'; content: string }[]) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data, error } = await supabase.functions.invoke('inkweaver-companion', {
    body: { projectId, messages }
  });
  if (error) {
    let detail = '';
    try {
      const response = (error as any).context;
      if (response && typeof response.clone === 'function') {
        const payload = await response.clone().json();
        detail = payload?.error || payload?.message || '';
      }
    } catch {
      // Keep the original invocation error when the response has no JSON body.
    }
    throw new Error(detail || error.message || 'The AI service request failed.');
  }
  if (!data?.answer) throw new Error(data?.error ?? 'The AI companion did not return an answer.');
  return data.answer as string;
}
