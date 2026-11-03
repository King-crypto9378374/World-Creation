import { useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';
import { Activity, Bell, BookOpen, Clock3, Globe2, Heart, Layers3, LogOut, MessageCircle, Radio, Send, Shield, Sparkles, Users } from 'lucide-react';
import { isSupabaseConfigured, supabase, loadWorldStatus, loadPrayers, loadWorldCounts, answerPrayer, createBroadcast, type PrayerRecord, type WorldStatus } from './lib/supabase';

export default function ConnectedApp() {
  const [session,setSession] = useState<any>(null);
  const [profile,setProfile] = useState<any>(null);
  const [email,setEmail] = useState('');
  const [password,setPassword] = useState('');
  const [authError,setAuthError] = useState('');
  const [busy,setBusy] = useState(false);
  const [world,setWorld] = useState<WorldStatus|null>(null);
  const [counts,setCounts] = useState({population:0,settlements:0});
  const [prayers,setPrayers] = useState<PrayerRecord[]>([]);
  const [selected,setSelected] = useState<PrayerRecord|null>(null);
  const [reply,setReply] = useState('');
  const [broadcast,setBroadcast] = useState('');
  const [toast,setToast] = useState('');
  const [now,setNow] = useState(Date.now());
  const [loadError,setLoadError] = useState('');
  const [active,setActive] = useState('Overview');
  const [citizens,setCitizens] = useState<any[]>([]);
  const [events,setEvents] = useState<any[]>([]);
  const [broadcasts,setBroadcasts] = useState<any[]>([]);
  const [selectedCitizen,setSelectedCitizen] = useState<any>(null);

  useEffect(()=>{
    if(!supabase) return;
    supabase.auth.getSession().then(({data})=>setSession(data.session));
    const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));
    return ()=>subscription.unsubscribe();
  },[]);

  useEffect(()=>{
    if(!session?.user || !supabase){setProfile(null);return;}
    let live=true;
    supabase.from('profiles').select('id,display_name,role').eq('id',session.user.id).single()
      .then(({data,error})=>{if(live){if(error)setLoadError(error.message);else setProfile(data);}});
    return ()=>{live=false;};
  },[session]);

  const refresh=async()=>{
    try{
      const [w,p]=await Promise.all([loadWorldStatus(),loadPrayers()]);
      setWorld(w);setPrayers(p);
      if(w) { setCounts(await loadWorldCounts(w.id));
        const [c,e,b]=await Promise.all([supabase!.from('citizens').select('id,full_name,age_years,status,traits,x,y,current_activity,settlement_id,birth_year,personality,ambitions,relationships,settlements(name,x,y)').eq('world_id',w.id).order('full_name'),supabase!.from('world_events').select('id,world_year,title,description,event_type').eq('world_id',w.id).order('world_year',{ascending:false}).limit(100),supabase!.from('broadcasts').select('id,message,issued_at_year,reach_status,created_at').eq('world_id',w.id).order('created_at',{ascending:false}).limit(100)]);
        if(c.error)throw c.error;if(e.error)throw e.error;if(b.error)throw b.error;setCitizens(c.data??[]);setEvents(e.data??[]);setBroadcasts(b.data??[]);
      }
      setLoadError('');
      setSelected(old=>old ? p.find(x=>x.id===old.id) ?? p[0] ?? null : p[0] ?? null);
    }catch(e){setLoadError(e instanceof Error?e.message:'Could not load world data.');}
  };
  useEffect(()=>{
    if(profile?.role!=='creator')return;
    refresh();
    const timer=window.setInterval(()=>{setNow(Date.now());refresh();},30000);
    const clock=window.setInterval(()=>setNow(Date.now()),1000);
    return ()=>{window.clearInterval(timer);window.clearInterval(clock);};
  },[profile?.role]);

  const simYear=world ? world.simulated_year+(world.paused?0:(now-Date.parse(world.real_now))/3600000) : 1;
  const localTime=useMemo(()=>new Intl.DateTimeFormat(undefined,{hour:'2-digit',minute:'2-digit',second:'2-digit'}).format(now),[now]);
  const notify=(s:string)=>{setToast(s);window.setTimeout(()=>setToast(''),3000);};

  const signIn=async(e:FormEvent)=>{
    e.preventDefault();if(!supabase)return;setBusy(true);setAuthError('');
    const {error}=await supabase.auth.signInWithPassword({email,password});
    if(error)setAuthError(error.message);setBusy(false);
  };
  const sendReply=async()=>{
    if(!selected||!session?.user||!reply.trim())return;
    setBusy(true);
    try{await answerPrayer(selected.id,session.user.id,reply.trim());setReply('');await refresh();notify('Your response has been saved.');}
    catch(e){notify(e instanceof Error?e.message:'Could not save response.');}
    finally{setBusy(false);}
  };
  const sendBroadcast=async()=>{
    if(!world||!session?.user||!broadcast.trim())return;
    setBusy(true);
    try{await createBroadcast(session.user.id,broadcast.trim(),simYear,world.id);setBroadcast('');notify('Broadcast saved to the world record.');}
    catch(e){notify(e instanceof Error?e.message:'Could not save broadcast.');}
    finally{setBusy(false);}
  };

  if(!isSupabaseConfigured||!supabase)return <div className="auth-screen"><div className="auth-card"><div className="brand-mark">E</div><div className="eyebrow">PROJECT ETHO · WORLD X-219B</div><h1>Connect the world.</h1><p>Supabase credentials are not configured in this deployment. Add the project URL and publishable/anon key as environment variables, then redeploy.</p><code>VITE_SUPABASE_URL</code><code>VITE_SUPABASE_ANON_KEY</code><small>Do not use a service-role key in the browser.</small></div></div>;

  if(!session)return <div className="auth-screen"><form className="auth-card" onSubmit={signIn}><div className="brand-mark">E</div><div className="eyebrow">CREATOR AUTHENTICATION</div><h1>Welcome back, Etho.</h1><p>Sign in to access the private world observatory.</p><label>Email address<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="username"/></label><label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="current-password"/></label>{authError&&<div className="auth-error">{authError}</div>}<button className="gold-button auth-submit" disabled={busy}>{busy?'Signing in…':'Enter the observatory'}</button><small>Accounts are created in Supabase Authentication. Creator access must be granted in the database by the project owner.</small></form></div>;

  if(profile?.role!=='creator')return <div className="auth-screen"><div className="auth-card"><div className="brand-mark">E</div><div className="eyebrow">ACCESS PENDING</div><h1>Creator approval required.</h1><p>This account is authenticated, but it has not been granted creator permissions.</p>{loadError&&<div className="auth-error">{loadError}</div>}<button className="gold-button auth-submit" onClick={()=>supabase?.auth.signOut()}>Sign out</button></div></div>;

  return <div className="shell">
    <aside className="sidebar"><div className="brand"><div className="brand-mark">E</div><div><b>PROJECT ETHO</b><span>WORLD OBSERVATORY</span></div></div><div className="creator-card"><div className="creator-icon"><Sparkles size={17}/></div><div><span>CREATOR ACCESS</span><b>ETHO</b></div><span className="online-dot"/></div><div className="nav-label">OBSERVATORY</div><nav>{[{name:"Overview",icon:Layers3},{name:"Humanity",icon:Users},{name:"Prayers",icon:Heart},{name:"World Map",icon:Globe2},{name:"Timeline",icon:BookOpen},{name:"Broadcasts",icon:Radio}].map(t=><button key={t.name} className={active===t.name?"nav-item active":"nav-item"} onClick={()=>setActive(t.name)}><t.icon size={17}/>{t.name}{t.name==="Prayers"&&<i>{prayers.length}</i>}</button>)}</nav><div className="sidebar-bottom"><div className="system-status"><span className="pulse"/><span>WORLD SYSTEM</span><b>DATABASE CONNECTED</b></div><button className="nav-item" onClick={()=>supabase?.auth.signOut()}><LogOut size={17}/>Sign out</button><div className="version">X-219B <span>·</span> LIVE WORLD</div></div></aside>
    <main className="main"><header className="topbar"><div className="breadcrumb">ETHO <span>› {active.toUpperCase()}</span></div><div className="top-actions"><div className="clock-chip"><span className="clock-dot"/><Clock3 size={14}/><span>YOUR TIME</span><b>{localTime}</b></div><div className="avatar">E</div></div></header>
      <div className="content"><div className="welcome"><div><div className="eyebrow"><span/> THE BEGINNING OF EVERYTHING</div><h1>{active==="Overview"?"A world awaits its story.":active}</h1><p>Humanity has taken its first steps. Watch their world become something greater.</p></div><div className="world-tag"><Globe2 size={15}/> WORLD X-219B</div></div>
        {active==="Overview"&&<><section className="time-panel"><div className="time-side"><span className="metric-label">ETHO · YOUR LOCAL TIME</span><div className="big-time">{localTime}</div><span className="subtle">{new Intl.DateTimeFormat(undefined,{dateStyle:'full'}).format(now)}</span></div><div className="time-divider"><div className="time-orb"><Clock3 size={19}/></div><span>TIME DILATION</span><b>1 : 1 YEAR</b></div><div className="time-side sim"><span className="metric-label">CIVILIZATION · SIMULATED TIME</span><div className="big-time">YEAR {Math.floor(simYear).toLocaleString()}</div><span className="subtle">{world?.paused?'World paused':'Advancing in real time'}</span></div><div className="time-progress"><div><span>WORLD YEAR PROGRESS</span><b>{Math.floor((simYear%1)*100)}%</b></div><div className="progress-track"><i style={{width:`${(simYear%1)*100}%`}}/></div></div></section>
        <div className="section-head"><div><div className="eyebrow">CIVILIZATION STATUS</div><h2>The first chapter</h2></div><span className="live-tag"><span/> {world?'DATABASE LIVE':'CONNECTING'}</span></div>
        <div className="stats-grid"><Stat icon={<Users/>} label="KNOWN POPULATION" value={String(counts.population)} note="Living citizens" /><Stat icon={<Heart/>} label="RECORDED PRAYERS" value={String(prayers.length).padStart(2,'0')} note="Stored in Supabase" /><Stat icon={<Globe2/>} label="SETTLEMENTS" value={String(counts.settlements)} note="Founded settlements" /><Stat icon={<Activity/>} label="CIVILIZATION ERA" value="Dawn" note="Before recorded history" /></div>
        {loadError&&<div className="data-error">{loadError}</div>}
        <div className="dashboard-grid"><section className="panel prayer-panel"><div className="panel-head"><div><div className="eyebrow">A CONNECTION TO HUMANITY</div><h3>Prayer inbox <span className="count">{prayers.length}</span></h3></div><button className="text-button" onClick={refresh}>Refresh ↻</button></div>
          {prayers.length===0?<div className="empty">No prayers have been recorded yet. They will appear here when the simulation engine creates them.</div>:prayers.slice(0,5).map(p=><button className={`prayer-row ${selected?.id===p.id?'selected':''}`} key={p.id} onClick={()=>setSelected(p)}><div className="prayer-avatar">{p.citizens?.full_name?.[0]??'?'}</div><div className="prayer-copy"><div><b>{p.citizens?.full_name??'Unknown citizen'}</b><span>{p.citizens?.settlements?.name??'Unknown settlement'} · Year {Math.floor(p.world_year)}</span></div><p>{p.message}</p><small>{p.emotional_state.toUpperCase()} · {p.status.toUpperCase()}</small></div></button>)}
        </section><section className="panel reply-panel"><div className="panel-head"><div><div className="eyebrow">DIVINE COMMUNICATION</div><h3>{selected?.citizens?.full_name??'Select a prayer'}</h3></div><div className="gold-icon"><MessageCircle size={17}/></div></div>{selected?<><blockquote>“{selected.message}”</blockquote><div className="reply-label">YOUR RESPONSE</div><textarea value={reply} onChange={e=>setReply(e.target.value)} placeholder="Send a message to this citizen..."/><button className="gold-button" onClick={sendReply} disabled={!reply.trim()||busy}><Send size={15}/> Save response</button><p className="fine-print"><Shield size={12}/> Stored in the permanent world record.</p></>:<div className="empty">Choose a prayer to read its message.</div>}</section></div>
        <section className="panel broadcast-panel"><div className="broadcast-icon"><Radio size={18}/></div><div className="broadcast-main"><div className="eyebrow">SPEAK TO THE WORLD</div><h3>Issue a creator broadcast</h3><p>Broadcasts are saved to the world record. Citizen delivery is a later simulation milestone.</p><div className="broadcast-input"><input value={broadcast} onChange={e=>setBroadcast(e.target.value)} onKeyDown={e=>e.key==='Enter'&&sendBroadcast()} placeholder="Write a message for humanity..."/><button onClick={sendBroadcast} disabled={!broadcast.trim()||busy}><Send size={15}/> Broadcast</button></div></div></section>
        {active!=="Overview"&&<section className="panel tab-content"><div className="panel-head"><div><div className="eyebrow">WORLD OBSERVATORY</div><h3>{active}</h3></div><button className="text-button" onClick={refresh}>Refresh ↻</button></div>
{active==="Humanity"&&<>{citizens.map(c=><div className="citizen-row" key={c.id}><div className="prayer-avatar">{c.full_name?.[0]??"?"}</div><div className="prayer-copy"><b>{c.full_name}</b><p>Age {c.age_years} · {c.settlements?.name??"Wilderness"} · {c.status}</p><small>{(c.traits??[]).join(" · ")}</small></div></div>)}{citizens.length===0&&<div className="empty">No citizens found.</div>}</>}
{active==="Prayers"&&<>{prayers.map(p=><button className="prayer-row" key={p.id} onClick={()=>setSelected(p)}><div className="prayer-avatar">{p.citizens?.full_name?.[0]??"?"}</div><div className="prayer-copy"><b>{p.citizens?.full_name??"Unknown citizen"}</b><p>{p.message}</p><small>{p.emotional_state} · {p.status} · Year {Math.floor(p.world_year)}</small></div></button>)}</>}
{active==="World Map"&&<><p className="map-note">This is the persistent world map. Each marker uses the citizen’s saved world coordinates; select a person to inspect their current life.</p><div className="world-map real-world-map"><div className="map-grid"/><svg className="world-land" viewBox="0 0 1000 600" preserveAspectRatio="none" aria-hidden="true"><path d="M55 145 L115 82 220 62 285 98 365 68 455 108 520 85 615 120 705 88 820 135 915 210 880 300 930 365 855 440 780 455 715 530 610 510 550 555 455 510 375 535 290 485 210 500 135 430 75 345 105 270Z"/><path d="M145 220 Q270 180 355 265 T550 280 T735 330 T880 285" className="map-river-path"/></svg>{settlements.map(s=><div className="settlement-pin" key={s.id} style={{left:(Number(s.x)*100)+"%",top:(Number(s.y)*100)+"%"}} title={s.name}><span>⌂</span><b>{s.name}</b></div>)}{citizens.filter(c=>c.status==="alive").map(c=><button className={selectedCitizen?.id===c.id?"citizen-pin selected":"citizen-pin"} key={c.id} style={{left:(Number(c.x??c.settlements?.x??.5)*100)+"%",top:(Number(c.y??c.settlements?.y??.5)*100)+"%"}} onClick={()=>setSelectedCitizen(c)} title={"Inspect "+c.full_name}><span/>{c.full_name}</button>)}</div><div className="map-legend"><span>● Living citizen</span><span>⌂ Settlement</span><span>{citizens.filter(c=>c.status==="alive").length} people plotted</span></div>{selectedCitizen&&<div className="citizen-inspector"><div className="prayer-avatar">{selectedCitizen.full_name?.[0]}</div><div className="inspector-main"><div className="eyebrow">CITIZEN PROFILE · {selectedCitizen.status?.toUpperCase()}</div><h3>{selectedCitizen.full_name}</h3><p>Age {selectedCitizen.age_years} · {selectedCitizen.settlements?.name??"Wilderness"}</p><p><b>Doing:</b> {selectedCitizen.current_activity??"Going about daily life"}</p><p><b>Traits:</b> {(selectedCitizen.traits??[]).join(", ")||"Not yet recorded"}</p><p><b>Ambitions:</b> {(selectedCitizen.ambitions??[]).join(", ")||"Not yet recorded"}</p></div><button className="text-button" onClick={()=>setSelectedCitizen(null)}>Close</button></div>}</>}
{active==="Timeline"&&<>{events.map(e=><div className="event-row" key={e.id}><span className="event-year">YEAR {Math.floor(e.world_year)}</span><div><b>{e.title}</b><p>{e.description}</p><small>{e.event_type}</small></div></div>)}{events.length===0&&<div className="empty">No events have been recorded yet.</div>}</>}
{active==="Broadcasts"&&<><div className="broadcast-input"><input value={broadcast} onChange={e=>setBroadcast(e.target.value)} onKeyDown={e=>e.key==="Enter"&&sendBroadcast()} placeholder="Write a message for humanity..."/><button onClick={sendBroadcast} disabled={!broadcast.trim()||busy}><Send size={15}/> Broadcast</button></div>{broadcasts.map(b=><div className="event-row" key={b.id}><span className="event-year">YEAR {Math.floor(b.issued_at_year)}</span><div><p>{b.message}</p><small>{b.reach_status}</small></div></div>)}</>}
</section>}
<footer><span>PROJECT ETHO <b>·</b> X-219B</span><span><Shield size={12}/> CREATOR CONSOLE <b>·</b> SUPABASE</span></footer>
      </div>
    </main>{toast&&<div className="toast"><Bell size={16}/>{toast}</div>}
  </div>;
}
function Stat({icon,label,value,note}:{icon:any;label:string;value:string;note:string}){return <div className="stat-card"><div className="stat-top"><span>{label}</span><i>{icon}</i></div><strong>{value}</strong><small>{note}</small></div>}
