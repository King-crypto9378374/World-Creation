import { useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { Activity, Bell, BookOpen, ChevronRight, CircleHelp, Clock3, Globe2, Heart, Layers3, LockKeyhole, Menu, MessageCircle, Radio, Send, Settings2, Shield, Sparkles, Users, X } from 'lucide-react';

type Prayer = { id: number; name: string; place: string; year: number; text: string; mood: string };
const START = Date.now();
const initialPrayers: Prayer[] = [
  { id: 1, name: 'Aren', place: 'The First Hearth', year: 1, text: 'If someone is listening beyond the sky, show us where the river goes. We have little food, and the young ones are afraid.', mood: 'Worried' },
  { id: 2, name: 'Sela', place: 'Eastern Riverbank', year: 1, text: 'Thank you for the rain. I do not know who to thank, but I wanted the words to exist somewhere.', mood: 'Grateful' }
];
const nav = [{label:'Overview',icon:Layers3},{label:'Humanity',icon:Users},{label:'Prayers',icon:Heart},{label:'World Map',icon:Globe2},{label:'Timeline',icon:BookOpen},{label:'Broadcasts',icon:Radio}];

export default function App() {
  const [now,setNow] = useState(Date.now());
  const [active,setActive] = useState('Overview');
  const [prayers,setPrayers] = useState(initialPrayers);
  const [selected,setSelected] = useState<Prayer | null>(initialPrayers[0]);
  const [reply,setReply] = useState('');
  const [broadcast,setBroadcast] = useState('');
  const [toast,setToast] = useState('');
  const [mobile,setMobile] = useState(false);
  useEffect(()=>{ const id=window.setInterval(()=>setNow(Date.now()),1000); return ()=>window.clearInterval(id); },[]);
  const elapsedYears = (now-START)/3600000;
  const simYear = 1+elapsedYears;
  const simDay = Math.floor((elapsedYears%1)*365)+1;
  const simHour = Math.floor(((elapsedYears*365)%1)*24);
  const localTime = useMemo(()=>new Intl.DateTimeFormat(undefined,{hour:'2-digit',minute:'2-digit',second:'2-digit'}).format(now),[now]);
  const notify=(s:string)=>{setToast(s);window.setTimeout(()=>setToast(''),2600)};
  const sendReply=()=>{if(!reply.trim()||!selected)return;notify('Reply recorded in this preview. Connect the simulation API to persist it.');setReply('');};
  const sendBroadcast=()=>{if(!broadcast.trim())return;notify('Broadcast drafted. Delivery and citizen reactions activate with the simulation engine.');setBroadcast('');};
  return <div className="shell">
    <aside className={`sidebar ${mobile?'mobile-open':''}`}>
      <div className="brand"><div className="brand-mark">E</div><div><b>PROJECT ETHO</b><span>WORLD OBSERVATORY</span></div><button className="icon-btn close-menu" onClick={()=>setMobile(false)}><X size={17}/></button></div>
      <div className="creator-card"><div className="creator-icon"><Sparkles size={17}/></div><div><span>CREATOR ACCESS</span><b>ETHO</b></div><span className="online-dot"/></div>
      <div className="nav-label">OBSERVATORY</div>
      <nav>{nav.map(n=><button key={n.label} onClick={()=>{setActive(n.label);setMobile(false)}} className={active===n.label?'nav-item active':'nav-item'}><n.icon size={17}/>{n.label}{n.label==='Prayers'&&<i>{prayers.length}</i>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="system-status"><span className="pulse"/><span>WORLD SYSTEM</span><b>PREVIEW MODE</b></div><button className="nav-item" onClick={()=>notify('Settings will be available when authentication is connected.')}><Settings2 size={17}/>Settings</button><div className="version">X-219B <span>·</span> FOUNDATION BUILD 0.1</div></div>
    </aside>
    <main className="main">
      <header className="topbar"><button className="icon-btn menu-btn" onClick={()=>setMobile(true)}><Menu size={19}/></button><div className="breadcrumb">ETHO <ChevronRight size={14}/> <span>{active.toUpperCase()}</span></div><div className="top-actions"><div className="clock-chip"><span className="clock-dot"/><Clock3 size={14}/><span>YOUR TIME</span><b>{localTime}</b></div><button className="icon-btn" onClick={()=>notify('No new system alerts.')}><Bell size={17}/></button><div className="avatar">E</div></div></header>
      <div className="content">
        <div className="welcome"><div><div className="eyebrow"><span/> THE BEGINNING OF EVERYTHING</div><h1>{active==='Overview'?'A world awaits its story.':active}</h1><p>{active==='Overview'?'Humanity has taken its first steps. Watch their world become something greater.':`Observe the unfolding story of humanity — ${active.toLowerCase()} from the creator’s perspective.`}</p></div><div className="world-tag"><Globe2 size={15}/> WORLD X-219B</div></div>
        <section className="time-panel"><div className="time-side"><span className="metric-label">ETHO · YOUR LOCAL TIME</span><div className="big-time">{localTime}</div><span className="subtle">{new Intl.DateTimeFormat(undefined,{dateStyle:'full'}).format(now)}</span></div><div className="time-divider"><div className="time-orb"><Clock3 size={19}/></div><span>TIME DILATION</span><b>1 : 1 YEAR</b></div><div className="time-side sim"><span className="metric-label">CIVILIZATION · SIMULATED TIME</span><div className="big-time">YEAR {Math.floor(simYear).toLocaleString()}</div><span className="subtle">Day {simDay} · {String(simHour).padStart(2,'0')}:00 world time</span></div><div className="time-progress"><div><span>WORLD YEAR PROGRESS</span><b>{Math.floor((simYear%1)*100)}%</b></div><div className="progress-track"><i style={{width:`${(simYear%1)*100}%`}}/></div></div></section>
        <div className="section-head"><div><div className="eyebrow">CIVILIZATION STATUS</div><h2>The first chapter</h2></div><span className="live-tag"><span/> LIVE CLOCK</span></div>
        <div className="stats-grid">
          <Stat icon={<Users/>} label="KNOWN POPULATION" value="12" note="The first generation" />
          <Stat icon={<Heart/>} label="RECORDED PRAYERS" value={String(prayers.length).padStart(2,'0')} note="Awaiting your attention" />
          <Stat icon={<Globe2/>} label="SETTLEMENTS" value="1" note="The First Hearth" />
          <Stat icon={<Activity/>} label="CIVILIZATION ERA" value="Dawn" note="Before recorded history" />
        </div>
        <div className="dashboard-grid">
          <section className="panel prayer-panel"><div className="panel-head"><div><div className="eyebrow">A CONNECTION TO HUMANITY</div><h3>Prayer inbox <span className="count">{prayers.length}</span></h3></div><button className="text-button" onClick={()=>setActive('Prayers')}>View all <ChevronRight size={14}/></button></div>
            {prayers.slice(0,3).map(p=><button className={`prayer-row ${selected?.id===p.id?'selected':''}`} key={p.id} onClick={()=>setSelected(p)}><div className="prayer-avatar">{p.name[0]}</div><div className="prayer-copy"><div><b>{p.name}</b><span>{p.place} · Year {p.year}</span></div><p>{p.text}</p><small>{p.mood.toUpperCase()} · CITIZEN PRAYER</small></div><ChevronRight size={16}/></button>)}
          </section>
          <section className="panel reply-panel"><div className="panel-head"><div><div className="eyebrow">DIVINE COMMUNICATION</div><h3>{selected?selected.name+' · '+selected.place:'Select a prayer'}</h3></div><div className="gold-icon"><MessageCircle size={17}/></div></div>{selected?<><blockquote>“{selected.text}”</blockquote><div className="reply-label">YOUR RESPONSE</div><textarea value={reply} onChange={e=>setReply(e.target.value)} placeholder="Send a message to this citizen..." /><button className="gold-button" onClick={sendReply} disabled={!reply.trim()}><Send size={15}/> Send response</button><p className="fine-print"><LockKeyhole size={12}/> Preview only — responses are not yet persisted.</p></>:<div className="empty">Choose a prayer to read its message.</div>}</section>
        </div>
        <section className="panel broadcast-panel"><div className="broadcast-icon"><Radio size={18}/></div><div className="broadcast-main"><div className="eyebrow">SPEAK TO THE WORLD</div><h3>Issue a creator broadcast</h3><p>Your words can reach citizens as communication systems develop.</p><div className="broadcast-input"><input value={broadcast} onChange={e=>setBroadcast(e.target.value)} onKeyDown={e=>e.key==='Enter'&&sendBroadcast()} placeholder="Write a message for humanity..." /><button onClick={sendBroadcast} disabled={!broadcast.trim()}><Send size={15}/> Broadcast</button></div></div></section>
        <footer><span>PROJECT ETHO <b>·</b> X-219B</span><span><Shield size={12}/> CREATOR CONSOLE <b>·</b> FOUNDATION PREVIEW</span></footer>
      </div>
    </main>
    {toast&&<div className="toast"><CircleHelp size={16}/>{toast}</div>}
  </div>;
}
function Stat({icon,label,value,note}:{icon:ReactNode;label:string;value:string;note:string}){return <div className="stat-card"><div className="stat-top"><span>{label}</span><i>{icon}</i></div><strong>{value}</strong><small>{note}</small></div>}
