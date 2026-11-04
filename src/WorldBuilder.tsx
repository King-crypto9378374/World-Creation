import { useRef, useState } from 'react';
import type { PointerEvent } from 'react';
import { Brush, Droplets, Mountain, Trees, Route, MapPin, Eraser, Undo2, Trash2 } from 'lucide-react';
type Tool='land'|'water'|'mountains'|'forest'|'road'|'erase'|'pin';
type Point={x:number;y:number};
type Stroke={id:string;tool:Tool;points:Point[];size:number};
type Marker={id:string;x:number;y:number;name:string};
type Props={world:any;onChange:(patch:any)=>void};
const colors:Record<Tool,string>={land:'#71845b',water:'#438eae',mountains:'#c6c1ae',forest:'#345d42',road:'#c7a45f',erase:'#102b3b',pin:'#e7c77f'};
const icons:Record<Tool,any>={land:Brush,water:Droplets,mountains:Mountain,forest:Trees,road:Route,erase:Eraser,pin:MapPin};
const label:Record<Tool,string>={land:'Land / coast',water:'Water',mountains:'Mountains',forest:'Forest',road:'Road / path',erase:'Eraser',pin:'Place marker'};
const makeId=()=>Math.random().toString(36).slice(2,10);
export default function WorldBuilder({world,onChange}:Props){
 const svg=useRef<SVGSVGElement>(null);
 const [tool,setTool]=useState<Tool>('land');
 const [size,setSize]=useState(28);
 const [draft,setDraft]=useState<Stroke|null>(null);
 const data=world.mapData||{strokes:[],markers:[]};
 const strokes:Stroke[]=data.strokes||[];
 const markers:Marker[]=data.markers||[];
 const point=(e:PointerEvent<SVGSVGElement>):Point=>{const r=e.currentTarget.getBoundingClientRect();return {x:Math.max(0,Math.min(1000,(e.clientX-r.left)/r.width*1000)),y:Math.max(0,Math.min(600,(e.clientY-r.top)/r.height*600))};};
 const start=(e:PointerEvent<SVGSVGElement>)=>{if(tool==='pin'){const name=window.prompt('Name this place on your map');if(name?.trim()){const p=point(e);onChange({mapData:{...data,markers:[...markers,{id:makeId(),x:p.x,y:p.y,name:name.trim()}]}});}return;}e.currentTarget.setPointerCapture(e.pointerId);setDraft({id:makeId(),tool,points:[point(e)],size});};
 const move=(e:PointerEvent<SVGSVGElement>)=>{if(draft)setDraft({...draft,points:[...draft.points,point(e)]});};
 const finish=()=>{if(draft){onChange({mapData:{...data,strokes:[...strokes,draft]}});setDraft(null);}};
 const draw=(s:Stroke)=>s.points.map((p,i)=>(i?'L ':'M ')+p.x+' '+p.y).join(' ');
 const renderStroke=(s:Stroke)=><path key={s.id} d={draw(s)} fill="none" stroke={colors[s.tool]} strokeWidth={s.size} strokeLinecap="round" strokeLinejoin="round" opacity={s.tool==='road'?.9:.92} strokeDasharray={s.tool==='road'?'12 8':undefined}/>;
 return <section className="iw-panel iw-map-editor">
  <div className="iw-map-editor-head"><div><span className="iw-eyebrow">CARTOGRAPHY WORKSHOP</span><h2>{world.name}</h2><p>Draw coastlines, terrain, paths, and place named locations. Changes autosave to this project.</p></div><div className="iw-map-count">{strokes.length} strokes · {markers.length} places</div></div>
  <div className="iw-map-tools">{(['land','water','mountains','forest','road','erase','pin'] as Tool[]).map(t=>{const Icon=icons[t];return <button key={t} className={tool===t?'active':''} onClick={()=>setTool(t)} title={label[t]}><Icon size={15}/><span>{label[t]}</span></button>;})}</div>
  <div className="iw-map-brush"><label>BRUSH SIZE <input type="range" min="5" max="80" value={size} onChange={e=>setSize(Number(e.target.value))}/><b>{size}px</b></label><div><button onClick={()=>onChange({mapData:{...data,strokes:strokes.slice(0,-1)}})} disabled={!strokes.length}><Undo2 size={13}/> Undo</button><button onClick={()=>{if(window.confirm('Clear all map drawings?'))onChange({mapData:{...data,strokes:[]}});}} disabled={!strokes.length}><Trash2 size={13}/> Clear drawings</button></div></div>
  <div className="iw-drawing-board"><svg ref={svg} viewBox="0 0 1000 600" preserveAspectRatio="none" onPointerDown={start} onPointerMove={move} onPointerUp={finish} onPointerCancel={finish} style={{cursor:'crosshair',touchAction:'none'}}>
   <defs><pattern id="iw-map-grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M40 0H0V40" fill="none" stroke="#d4d0b5" strokeOpacity=".08" strokeWidth="1"/></pattern><filter id="iw-map-glow"><feGaussianBlur stdDeviation="5"/></filter></defs>
   <rect width="1000" height="600" fill="#102b3b"/><rect width="1000" height="600" fill="url(#iw-map-grid)"/>
   <path d="M60 180 Q145 70 285 115 T510 92 Q650 60 770 140 T955 220 L925 430 Q820 530 690 470 T450 520 Q280 570 180 450 T60 180Z" fill="#71845b" opacity=".15" stroke="#d3c59a" strokeOpacity=".2" strokeWidth="2"/>
   {strokes.map(renderStroke)}{draft&&renderStroke(draft)}
   {markers.map(m=><g key={m.id} transform={'translate('+m.x+' '+m.y+')'}><circle r="13" fill="#e7c77f" opacity=".18" filter="url(#iw-map-glow)"/><path d="M0 -13 C-15 -13 -16 5 0 19 C16 5 15 -13 0 -13Z" fill="#e7c77f" stroke="#352a18" strokeWidth="2"/><circle cy="-5" r="4" fill="#2b2419"/><text x="18" y="4" fill="#f4e8c9" fontSize="17" paintOrder="stroke" stroke="#13232a" strokeWidth="5">{m.name}</text></g>)}
  </svg><div className="iw-map-compass">N ↑</div><div className="iw-map-hint">{tool==='pin'?'Click anywhere to place a named location':'Click and drag to draw on your world'}</div></div>
  <div className="iw-map-key">{(['land','water','mountains','forest','road'] as Tool[]).map(t=><span key={t}><i style={{background:colors[t]}}/>{label[t]}</span>)}</div>
  <div className="iw-map-places"><div className="iw-panel-title"><span>MAP LOCATIONS · {markers.length}</span></div>{markers.map(m=><div key={m.id}><MapPin size={13}/><input value={m.name} onChange={e=>onChange({mapData:{...data,markers:markers.map(x=>x.id===m.id?{...x,name:e.target.value}:x)}})}/><button onClick={()=>onChange({mapData:{...data,markers:markers.filter(x=>x.id!==m.id)}})}>Remove</button></div>)}{!markers.length&&<p>Add the Place marker tool to label cities, ruins, kingdoms, and landmarks.</p>}</div>
 </section>;
}
