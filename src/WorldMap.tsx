import { useMemo, useState } from 'react';
import type { PointerEvent } from 'react';

type Props = {
  features: any[];
  civilizations: any[];
  borders: any[];
  settlements: any[];
  locations: any[];
  citizens: any[];
  journeys: any[];
  buildings: any[];
  selectedCitizen: any;
  onSelectCitizen: (citizen: any) => void;
};

const safePoints = (value: any): any[] => Array.isArray(value) ? value.filter((p:any)=>Array.isArray(p)&&Number.isFinite(Number(p[0]))&&Number.isFinite(Number(p[1]))) : [];
const pointString = (points: any) => safePoints(points).map((p:any) => (Number(p[0])*1000)+','+(Number(p[1])*600)).join(' ');

export default function WorldMap({features,civilizations,borders,settlements,locations,citizens,journeys,buildings,selectedCitizen,onSelectCitizen}:Props) {
  const [zoom,setZoom]=useState(1);
  const [pan,setPan]=useState({x:0,y:0});
  const [drag,setDrag]=useState<{x:number;y:number;px:number;py:number}|null>(null);
  const alive=useMemo(()=>citizens.filter(c=>c.status==='alive'),[citizens]);
  const selectedCiv=civilizations[0];
  const terrain=(type:string)=>features.filter(f=>f.feature_type===type);
  const startDrag=(e:PointerEvent<SVGSVGElement>)=>{setDrag({x:e.clientX,y:e.clientY,px:pan.x,py:pan.y});e.currentTarget.setPointerCapture(e.pointerId);};
  const moveDrag=(e:React.PointerEvent<SVGSVGElement>)=>{if(drag)setPan({x:drag.px+(e.clientX-drag.x)*1000/Math.max(1,e.currentTarget.clientWidth),y:drag.py+(e.clientY-drag.y)*600/Math.max(1,e.currentTarget.clientHeight)});};
  const stopDrag=()=>setDrag(null);
  const changeZoom=(amount:number)=>setZoom(v=>Math.max(1,Math.min(4,Number((v+amount).toFixed(2)))));
  return <div className="atlas-shell">
    <div className="atlas-toolbar"><div><b>WORLD ATLAS</b><span>Generated terrain · persistent world coordinates</span></div><div className="atlas-controls"><button onClick={()=>changeZoom(-.25)} aria-label="Zoom out">−</button><span>{Math.round(zoom*100)}%</span><button onClick={()=>changeZoom(.25)} aria-label="Zoom in">+</button><button onClick={()=>{setZoom(1);setPan({x:0,y:0});}}>Reset</button></div></div>
    <div className="atlas-viewport"><svg viewBox="0 0 1000 600" role="img" aria-label="Interactive fictional world map. Drag to pan and use plus or minus to zoom." onPointerDown={startDrag} onPointerMove={moveDrag} onPointerUp={stopDrag} onPointerCancel={stopDrag} onWheel={e=>changeZoom(e.deltaY<0?.15:-.15)}>
      <defs>
        <linearGradient id="ocean" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#17384a"/><stop offset="1" stopColor="#081d2a"/></linearGradient>
        <linearGradient id="land" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#81906a"/><stop offset=".5" stopColor="#566f53"/><stop offset="1" stopColor="#354d43"/></linearGradient>
        <pattern id="terrainTexture" width="28" height="28" patternUnits="userSpaceOnUse"><path d="M0 14 Q7 8 14 14 T28 14" fill="none" stroke="#d0d2a0" strokeOpacity=".08"/></pattern>
      </defs>
      <rect width="1000" height="600" fill="url(#ocean)"/>
      <g transform={`translate(${pan.x} ${pan.y}) translate(500 300) scale(${zoom}) translate(-500 -300)`}>
        <path d="M34 168 L76 110 151 78 228 89 290 55 367 78 430 53 506 84 581 65 648 91 714 76 797 111 872 142 950 214 923 284 966 348 917 423 849 452 795 511 713 500 653 548 572 525 508 568 420 532 341 550 267 504 189 521 118 457 66 388 80 309 42 249Z" fill="url(#land)" stroke="#b6b58b" strokeWidth="3"/>
        <path d="M34 168 L76 110 151 78 228 89 290 55 367 78 430 53 506 84 581 65 648 91 714 76 797 111 872 142 950 214 923 284 966 348 917 423 849 452 795 511 713 500 653 548 572 525 508 568 420 532 341 550 267 504 189 521 118 457 66 388 80 309 42 249Z" fill="url(#terrainTexture)"/>
        <path d="M112 120 Q220 170 312 119 T500 130 T700 130 T890 205" fill="none" stroke="#d9dfbd" strokeOpacity=".28" strokeWidth="2"/>
        <path d="M120 450 Q250 390 350 440 T590 450 T840 430" fill="none" stroke="#d9dfbd" strokeOpacity=".22" strokeWidth="2"/>
        {terrain('river').map(f=><polyline key={f.id} points={pointString(f.coordinates)} fill="none" stroke="#66b5d0" strokeWidth="10" strokeLinecap="round" strokeLinejoin="round"/>)}
        {terrain('river').map(f=><polyline key={f.id+'bank'} points={pointString(f.coordinates)} fill="none" stroke="#b1d9d9" strokeOpacity=".45" strokeWidth="2" strokeLinecap="round"/>)}
        {terrain('mountain_range').map(f=><g key={f.id}><polyline points={pointString(f.coordinates)} fill="none" stroke="#d2d1bb" strokeWidth="19" strokeLinecap="round" strokeLinejoin="round" opacity=".5"/>{safePoints(f.coordinates).map((p:any,i:number)=><path key={i} d={`M${p[0]*1000-17} ${p[1]*600+16} l17 -38 17 38 Z`} fill="#aeb5aa" stroke="#e1e2d5" strokeWidth="2"/>)}</g>)}
        {terrain('forest').map(f=><g key={f.id}>{safePoints(f.coordinates).map((p:any,i:number)=><g key={i} transform={`translate(${p[0]*1000} ${p[1]*600})`}><circle r="18" fill="#234b39" opacity=".88"/><circle cy="-5" r="12" fill="#47734b"/><circle cy="-10" r="7" fill="#78936a"/></g>)}</g>)}
        {terrain('lake').map(f=><polygon key={f.id} points={pointString(f.coordinates)} fill="#4e9fbd" stroke="#b4d6d9" strokeWidth="3"/>)}
        {terrain('wetland').map(f=><polygon key={f.id} points={pointString(f.coordinates)} fill="#667d57" stroke="#9aa978" strokeWidth="3" opacity=".85"/>)}
        {terrain('plains').map(f=><polyline key={f.id} points={pointString(f.coordinates)} fill="none" stroke="#b9ad70" strokeWidth="26" strokeOpacity=".28" strokeLinecap="round"/>)}
        {borders.filter(b=>b.is_current).map(b=><polygon key={b.id} points={pointString(b.polygon)} fill={civilizations.find(c=>c.id===b.civilization_id)?.color??'#d5b36b'} fillOpacity=".13" stroke={civilizations.find(c=>c.id===b.civilization_id)?.color??'#d5b36b'} strokeWidth="3" strokeDasharray="10 7"/>)}
        {journeys.map(j=>{const c=citizens.find(x=>x.id===j.citizen_id);const d=locations.find(x=>x.id===j.destination_location_id);return c&&d?<line key={j.id} x1={Number(c.x)*1000} y1={Number(c.y)*600} x2={Number(d.x)*1000} y2={Number(d.y)*600} stroke="#f4d783" strokeWidth="3" strokeDasharray="7 6"/>:null})}
        {locations.map(l=><g key={l.id} transform={`translate(${Number(l.x)*1000} ${Number(l.y)*600})`}><circle r="5" fill={l.location_type==='settlement'?'#f4d783':'#9ccbd0'} stroke="#17232b" strokeWidth="2"/><text x="9" y="-8" fill="#f4e8c6" fontSize="12" paintOrder="stroke" stroke="#1b2a2b" strokeWidth="3">{l.name}</text></g>)}
        {settlements.map(s=><g key={s.id} transform={`translate(${Number(s.x)*1000} ${Number(s.y)*600})`}><rect x="-7" y="-7" width="14" height="14" rx="2" fill="#f1c76e" stroke="#fff1c9" strokeWidth="2"/><text x="12" y="4" fill="#fff0c9" fontSize="13" paintOrder="stroke" stroke="#15221e" strokeWidth="4">{s.name}</text></g>)}
        {buildings.map(b=><g key={b.id} transform={`translate(${Number(b.x)*1000} ${Number(b.y)*600})`}><rect x="-5" y="-5" width="10" height="10" rx="1.5" fill={b.building_type==='farm'?'#9cbd76':'#d6b77a'} stroke="#26352b" strokeWidth="1.5"><title>{b.name} · {b.building_type}</title></rect></g>)}
        {alive.map(c=><g key={c.id} transform={`translate(${Number(c.x??c.settlements?.x??.5)*1000} ${Number(c.y??c.settlements?.y??.5)*600})`} onClick={()=>onSelectCitizen(c)} style={{cursor:'pointer'}}><circle r={selectedCitizen?.id===c.id?10:6} fill={selectedCitizen?.id===c.id?'#ffffff':'#f3d17e'} stroke="#18252b" strokeWidth="2"/><circle r="14" fill="none" stroke="#f3d17e" strokeOpacity=".28"/><title>{c.full_name} · age {c.age_years}</title></g>)}
      </g>
    </svg><div className="atlas-compass">N ↑</div><div className="atlas-scale">X-219B · {selectedCiv?.name??'Unclaimed lands'}</div></div>
    <div className="atlas-legend"><span><i className="legend-person"/> Citizens ({alive.length})</span><span><i className="legend-town"/> Settlements ({settlements.length})</span><span>▦ Buildings ({buildings.length})</span><span><i className="legend-river"/> Rivers & lakes</span><span><i className="legend-border"/> Civilization borders</span><span><i className="legend-mountain"/> Mountain ranges</span></div>
    <div className="atlas-civilizations">{civilizations.map(c=><div key={c.id}><i style={{background:c.color}}/><b>{c.name}</b><span>{c.government_type} · {c.population} people</span></div>)}</div>
  </div>;
}
