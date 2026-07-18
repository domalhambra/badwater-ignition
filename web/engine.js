"use strict";
//====================== BadwaterCore port — pure engine ======================
// This file is the web twin of Sources/BadwaterCore. It must stay free of DOM,
// state, storage, and clock access so Node can load it directly: the CI
// conformance harness (conformance/check-web.js) executes every function below
// against golden vectors generated from the Swift core. If you change anything
// here, the harness tells you whether you still match the iOS app — and if you
// change BadwaterCore, the regenerated vectors tell you to come back here.

// Table A — reference fuel moisture (6 temp rows x 21 RH cols)
const REF_GRID=[
 [1,2,2,3,4,5,5,6,7,8,8,8,9,9,10,11,12,12,13,13,14],
 [1,2,2,3,4,5,5,6,7,7,7,8,9,9,10,10,11,12,13,13,13],
 [1,2,2,3,4,5,5,6,6,7,7,8,8,9,9,10,11,12,12,12,13],
 [1,1,2,2,3,4,5,5,6,7,7,8,8,8,9,10,10,11,12,12,13],
 [1,1,2,2,3,4,4,5,6,7,7,8,8,8,9,10,10,11,12,12,13],
 [1,1,2,2,3,4,4,5,6,7,7,8,8,8,9,10,10,11,12,12,12]];
function refTempRow(t){ if(t<30)return 0; if(t<=49)return 1; if(t<=69)return 2; if(t<=89)return 3; if(t<=109)return 4; return 5; }
function refRhCol(rh){ rh=Math.min(100,Math.max(0,rh)); if(rh>=100)return 20; return Math.floor(rh/5); }
function referenceFM(t,rh){ return REF_GRID[refTempRow(t)][refRhCol(rh)]; }

// Tables B/C/D — corrections (unshaded 8 rows, shaded 4 rows; 18 cols)
const CORR={
 B:{u:[[2,3,4,1,1,1,0,0,1,0,0,1,1,1,1,2,3,4],[3,4,4,1,2,2,1,1,2,1,1,2,1,2,2,3,4,4],[2,2,3,1,1,1,0,0,1,0,0,1,1,1,2,3,4,4],[1,2,2,0,0,1,0,0,1,1,1,2,2,3,4,4,5,6],[2,3,3,1,1,1,0,0,1,0,0,1,1,1,1,2,3,3],[2,3,3,1,1,2,0,1,1,0,1,1,1,1,2,2,3,3],[2,3,4,1,1,2,0,0,1,0,0,1,0,1,1,2,3,3],[4,5,6,2,3,4,1,1,2,0,0,1,0,0,1,1,2,2]],
    s:[[4,5,5,3,4,5,3,3,4,3,3,4,3,4,5,4,5,5],[4,4,5,3,4,5,3,3,4,3,4,4,3,4,5,4,5,6],[4,4,5,3,4,5,3,3,4,3,3,4,3,4,5,4,5,5],[4,5,6,3,4,5,3,3,4,3,3,4,3,4,5,4,4,5]]},
 C:{u:[[3,4,5,1,2,3,1,1,2,1,1,2,1,2,3,3,4,5],[3,4,5,3,3,4,2,3,4,2,3,4,3,3,4,3,4,5],[3,4,5,1,2,3,1,1,1,1,1,2,1,2,4,3,4,5],[3,3,4,1,1,1,1,1,1,1,2,3,3,4,5,4,5,6],[3,4,5,1,2,2,1,1,1,1,1,1,1,2,3,3,4,5],[3,4,5,1,2,2,0,1,1,0,1,1,1,2,2,3,4,5],[3,4,5,1,2,3,1,1,1,1,1,1,1,2,3,3,4,5],[4,5,6,3,4,5,1,2,3,1,1,1,1,1,1,3,3,4]],
    s:[[4,5,6,4,5,5,3,4,5,3,4,5,4,5,5,4,5,6],[4,5,6,3,4,5,3,4,5,3,4,5,4,5,6,4,5,6],[4,5,6,3,4,5,3,4,5,3,4,5,3,4,5,4,5,6],[4,5,6,4,5,6,3,4,5,3,4,5,3,4,5,4,5,6]]},
 D:{u:[[4,5,6,3,4,5,2,3,4,2,3,4,3,4,5,4,5,6],[4,5,6,4,5,6,4,5,6,4,5,6,4,5,6,4,5,6],[4,5,6,3,4,4,2,3,3,2,3,3,3,4,5,4,5,6],[4,5,6,2,3,4,2,2,3,3,4,4,4,5,6,4,5,6],[4,5,6,3,4,5,2,3,3,2,2,3,3,4,4,4,5,6],[4,5,6,2,3,3,1,1,2,1,1,2,2,3,3,4,5,6],[4,5,6,3,4,5,2,3,3,2,3,3,3,4,4,4,5,6],[4,5,6,4,5,6,3,4,4,2,2,3,2,3,4,4,5,6]],
    s:[[4,5,6,4,5,6,4,5,6,4,5,6,4,5,6,4,5,6],[4,5,6,4,5,6,4,5,6,4,5,6,4,5,6,4,5,6],[4,5,6,4,5,6,4,5,6,4,5,6,4,5,6,4,5,6],[4,5,6,4,5,6,4,5,6,4,5,6,4,5,6,4,5,6]]}};
const ASPECTS=["N","E","S","W"];
const DELTAS=["below","level","above"];
function correction(group,shaded,aspect,steep,bandIdx,delta){
  const g=CORR[group]; const col=bandIdx*3+DELTAS.indexOf(delta);
  if(shaded){ return g.s[ASPECTS.indexOf(aspect)][col]; }
  return g.u[ASPECTS.indexOf(aspect)*2+(steep?1:0)][col];
}

// PIG table (9 temp rows x 16 FFM cols, FFM 2..17)
const PIG_U=[
 [100,100,80,70,60,60,50,40,40,30,30,20,20,20,20,10],
 [100,90,80,70,60,60,50,40,40,30,30,20,20,20,10,10],
 [100,90,80,70,60,50,40,40,30,30,30,20,20,20,10,10],
 [100,90,80,70,60,50,40,40,30,30,20,20,20,10,10,10],
 [100,80,70,60,60,50,40,40,30,30,20,20,20,10,10,10],
 [90,80,70,60,50,50,40,30,30,20,20,20,20,10,10,10],
 [90,80,70,60,50,40,40,30,30,20,20,20,10,10,10,10],
 [90,80,70,60,50,40,40,30,30,20,20,20,10,10,10,10],
 [80,70,60,50,50,40,30,30,20,20,20,10,10,10,10,10]];
const PIG_S=[
 [100,90,80,70,60,50,50,40,40,30,30,20,20,20,10,10],
 [100,90,80,70,60,50,50,40,30,30,30,20,20,20,10,10],
 [100,90,80,70,60,50,40,40,30,30,20,20,20,10,10,10],
 [100,80,70,60,60,50,40,40,30,30,20,20,20,10,10,10],
 [90,80,70,60,50,50,40,30,30,30,20,20,20,10,10,10],
 [90,80,70,60,50,40,40,30,30,20,20,20,10,10,10,10],
 [90,80,70,60,50,40,40,30,30,20,20,20,10,10,10,10],
 [90,80,60,50,50,40,30,30,30,20,20,20,10,10,10,10],
 [80,80,60,50,50,40,30,30,20,20,20,10,10,10,10,10]];
function pigTempRow(t){ if(t>=110)return 0; if(t>=100)return 1; if(t>=90)return 2; if(t>=80)return 3; if(t>=70)return 4; if(t>=60)return 5; if(t>=50)return 6; if(t>=40)return 7; return 8; }
function pigFfmCol(f){ return Math.min(Math.max(f-2,0),15); }
function pig(t,ffm,shaded){ return (shaded?PIG_S:PIG_U)[pigTempRow(t)][pigFfmCol(ffm)]; }

// Fire behavior interpretation
const BEHAV=[
 {t:"Very Low",r:"<10%",d:"Very low ignition, some spotting may occur with wind"},
 {t:"Low",r:"10 to 20%",d:"Low ignition, campfires can be hazardous"},
 {t:"Medium",r:"20 to 30%",d:"Medium ignition, matches hazardous, easy burning"},
 {t:"High",r:"30 to 50%",d:"High ignition, matches dangerous, spotting possible with wind, medium burning conditions"},
 {t:"Very High",r:"50 to 70%",d:"Very high ignition, rapid buildup, extensive spotting and crowning, and loss of control"},
 {t:"Extreme",r:"80 to 100%",d:"Extreme ignition and initial spread, frequent spots, critical fire conditions"}];
const CAUTION="Use these thresholds with caution; consult local experts.";
function behavior(p){ if(p<10)return 0; if(p<20)return 1; if(p<30)return 2; if(p<50)return 3; if(p<80)return 4; return 5; }

function monthGroup(m){ if(m===5||m===6||m===7)return"B"; if(m===11||m===12||m===1)return"D"; return"C"; }
const MONTHS=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
function groupMonths(g){ return g==="B"?"May Jun Jul":g==="D"?"Nov Dec Jan":"Feb Mar Apr Oct"; }
const TIMEBANDS=["0800-0959","1000-1159","1200-1359","1400-1559","1600-1759","1800-1959"];
// 2000–0759 is night (the IRPG "+5" rule) — the pre-0800 hours must fall
// through to night, not into the first daytime bands.
function timeBandFromClock(h,m){ const x=h*60+m; if(x<480)return "night"; if(x<600)return 0; if(x<720)return 1; if(x<840)return 2; if(x<960)return 3; if(x<1080)return 4; if(x<1200)return 5; return "night"; }

// Psychrometrics (Bolton + Ferrel sling)
const INHG_HPA=33.86389;
function esat(c){ return 6.112*Math.exp((17.67*c)/(c+243.5)); }
const f2c=f=>(f-32)*5/9, c2f=c=>c*9/5+32;
function psychro(dryF,wetF,pInHg){
  const wet=Math.min(wetF,dryF); const tD=f2c(dryF),tW=f2c(wet); const P=pInHg*INHG_HPA;
  const esD=esat(tD),esW=esat(tW); const k=0.000660*(1+0.00115*tW);
  let vp=esW-k*P*(tD-tW); if(vp<0.01)vp=0.01;
  const rh=Math.max(0,Math.min(100,100*vp/esD));
  const ratio=Math.log(vp/6.112); const dewC=(243.5*ratio)/(17.67-ratio);
  return {rh:Math.round(rh),dew:Math.round(c2f(dewC)),dep:Math.round(dryF-wet)};
}
const BANDS=[{n:1,p:30,l:"0–500 ft"},{n:2,p:29,l:"501–1,900 ft"},{n:3,p:27,l:"1,901–3,900 ft"},{n:4,p:25,l:"3,901–6,100 ft"},{n:5,p:23,l:"6,101–8,500 ft"},{n:6,p:21,l:"8,501–11,000  ft"}];
function bandByNum(n){ return BANDS.find(b=>b.n===n)||BANDS[2]; }
function bandForElev(feet,ak){
  if(ak){ if(feet<301)return 1; if(feet<=1700)return 2; if(feet<=3600)return 3; if(feet<=5700)return 4; if(feet<=7900)return 5; return 6; }
  if(feet<501)return 1; if(feet<=1900)return 2; if(feet<=3900)return 3; if(feet<=6100)return 4; if(feet<=8500)return 5; return 6;
}

// Wind
const DIRNAME={N:"North",E:"East",S:"South",W:"West",NE:"Northeast",SE:"Southeast",SW:"Southwest",NW:"Northwest"};
const DIRS=["N","NE","E","SE","S","SW","W","NW"];
function windRendered(w){ return w.low===w.high?String(w.high):w.low+"-"+w.high; }
function windSpot(w){ if(w.high<=0)return"Calm"; const d=w.dir?w.dir+" ":""; const g=w.gust>0?" Gust "+w.gust:""; return d+windRendered(w)+g; }
function windSpoken(w){ const g=w.gust>0?", with gusts up to "+w.gust:""; if(w.high<=0)return"light and variable"+g; const unit=(w.low===w.high&&w.low===1)?"mile per hour":"miles per hour"; const d=w.dir?" from the "+DIRNAME[w.dir]:""; return `${windRendered(w)} ${unit}${d}`+g; }
// IMET column E: speed-first, full direction word (e.g. "3-6 Southwest, Gust 12", "Light/Variable")
function windImet(w){ const g=w.gust>0?", Gust "+w.gust:""; if(w.high<=0)return"Light/Variable"+g; const d=w.dir?" "+DIRNAME[w.dir]:""; return windRendered(w)+d+g; }

// Estimate — o: {dryBulbF, rh, month, timeBand (0-5 | "night"), aspect, slope, elevationDelta}
function estimate(o){
  const rf=referenceFM(o.dryBulbF,o.rh);
  const night=o.timeBand==="night"; const g=monthGroup(o.month);
  function side(shaded){
    let corr=null,ffm;
    if(night){ ffm=rf+5; } else { corr=correction(g,shaded,o.aspect,o.slope==="steep",o.timeBand,o.elevationDelta); ffm=rf+corr; }
    const p=pig(o.dryBulbF,ffm,shaded); return {corr,ffm,pig:p,b:behavior(p)};
  }
  return {rf,night,unshaded:side(false),shaded:side(true)};
}

//====================== Shared formatting ======================
function hhmm(min){ const h=Math.floor(min/60)%24,m=min%60; return String(h).padStart(2,"0")+String(m).padStart(2,"0"); }
function grouped(v){ return v.toLocaleString("en-US"); }
function dateCode(ms){ const d=new Date(ms); return `${d.getMonth()+1}${d.getDate()}${d.getFullYear()%100}`; }
function dateSlash(ms){ const d=new Date(ms); return `${d.getMonth()+1}/${d.getDate()}/${d.getFullYear()%100}`; }

//====================== Radio script (port of BadwaterCore RadioScript) ======================
// cur/prev: logged-obs records {min,temp,rh,pigU,pigS,wind,aspect,slope,elevationFeet,spokenLocation}
function broadcastScript(addressee,cur,prev){
  const sent=[];
  const name=(addressee||"").trim();
  sent.push(name?`${name}, stand by for your ${hhmm(cur.min)} Weather observation.`:`Stand by for your ${hhmm(cur.min)} Weather observation.`);
  const speak = !prev || prev.elevationFeet!==cur.elevationFeet || prev.aspect!==cur.aspect || prev.slope!==cur.slope || (prev.spokenLocation||"")!==(cur.spokenLocation||"");
  if(speak){
    let s="Taken",detail=false;
    if(cur.spokenLocation){ s+=" "+cur.spokenLocation; detail=true; }
    if(cur.elevationFeet!=null){ s+=` at an elevation of ${grouped(cur.elevationFeet)} feet`; detail=true; }
    const adj={N:"Northern",E:"Eastern",S:"Southern",W:"Western"}[cur.aspect];
    const steep=cur.slope==="steep"; const art=steep?"a":(cur.aspect==="E"?"an":"a");
    const desc=steep?`steep ${adj}`:adj;
    s+= (detail?`, on ${art} ${desc} aspect.`:` on ${art} ${desc} aspect.`);
    sent.push(s);
  }
  const tDelta=prev?delta(cur.temp-prev.temp):""; const rDelta=prev?delta(cur.rh-prev.rh):"";
  const bodyC=`Dry Bulb ${cur.temp} degrees${tDelta}, RH ${cur.rh}%${rDelta}`;
  sent.push(bodyC+".");
  const pigS=`Probability of Ignition Unshaded is ${cur.pigU}%, Shaded is ${cur.pigS}%.`;
  // A recorded wind (speed range or gust) is spoken; {high:0,gust:0} means "not
  // recorded" and stays silent — matching the iOS RadioScript, where `wind` is
  // optional on the obs. (Previously tested `wind.speed`, a field this model
  // doesn't have, so measured winds were skipped unless gusting.)
  sent.push(cur.wind.high>0||cur.wind.gust>0?`Winds are ${windSpoken(cur.wind)}, ${pigS}`:pigS);
  sent.push(`I repeat, ${bodyC}.`);
  sent.push("How copy?");
  return sent.join(" ");
}
function delta(d){ if(d===0)return", no change"; return d>0?`, up ${d}`:`, down ${-d}`; }

//====================== IMET .xlsx (store-only zip, ported from BadwaterCore) ======================
const CRC_TABLE=(()=>{ const t=new Uint32Array(256); for(let i=0;i<256;i++){ let c=i; for(let k=0;k<8;k++){ c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1); } t[i]=c>>>0; } return t; })();
function crc32(bytes){ let c=0xFFFFFFFF; for(let i=0;i<bytes.length;i++){ c=CRC_TABLE[(c^bytes[i])&0xFF]^(c>>>8); } return (c^0xFFFFFFFF)>>>0; }
function le16(v){ return [v&0xFF,(v>>>8)&0xFF]; }
function le32(v){ return [v&0xFF,(v>>>8)&0xFF,(v>>>16)&0xFF,(v>>>24)&0xFF]; }
function zipStore(entries){
  const enc=new TextEncoder(); const out=[]; const central=[]; const dosTime=0,dosDate=0x21;
  for(const e of entries){
    const name=Array.from(enc.encode(e.path)); const bytes=Array.from(e.bytes);
    const crc=crc32(e.bytes); const size=bytes.length; const offset=out.length;
    out.push(...le32(0x04034b50),...le16(20),...le16(0),...le16(0),...le16(dosTime),...le16(dosDate),
      ...le32(crc),...le32(size),...le32(size),...le16(name.length),...le16(0),...name,...bytes);
    central.push(...le32(0x02014b50),...le16(20),...le16(20),...le16(0),...le16(0),...le16(dosTime),...le16(dosDate),
      ...le32(crc),...le32(size),...le32(size),...le16(name.length),...le16(0),...le16(0),...le16(0),...le16(0),
      ...le32(0),...le32(offset),...name);
  }
  const cdOffset=out.length,cdSize=central.length;
  const eocd=[...le32(0x06054b50),...le16(0),...le16(0),...le16(entries.length),...le16(entries.length),
    ...le32(cdSize),...le32(cdOffset),...le16(0)];
  return new Uint8Array([...out,...central,...eocd]);
}
// shifts: [{obs,division,locationName,dateMs}] — the retained days, oldest data
// first is not required (sorted here); the LAST entry must be the current shift
// (its header fields seed the empty-book fallback sheet, as the Swift export
// does with the live shift).
function buildXlsx(shifts,coordLat,coordLon){
  const enc=new TextEncoder();
  const H='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
  const headers=["Time","Dry Bulb","Wet Bulb","RH (%)","Wind (MPH)","Probability of Ignition (Unshaded) (%)","Probability of Ignition (Shaded) (%)","Elevation","Aspect","Location","Notes"];
  const disclaimer="Probability of Ignition = IRPG value, app-computed (not observed, not a forecast). Logged with Badwater Ignition - decision-support only, not affiliated with NWS/NWCG.";
  const col=i=>String.fromCharCode(65+i);
  const numC=(r,v)=>`<c r="${r}"><v>${v}</v></c>`;
  const strC=(r,v)=>`<c r="${r}" t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;
  const ns="http://schemas.openxmlformats.org/spreadsheetml/2006/main";
  const rel="http://schemas.openxmlformats.org/officeDocument/2006/relationships";
  const pkg="http://schemas.openxmlformats.org/package/2006/relationships";

  // One sheet per retained day (shift) that has obs — oldest first; empty shifts
  // skipped; an all-empty book still yields one header-only sheet. Mirrors the
  // Swift IMETExport.sheets(from: [Shift]).
  let sheetShifts=shifts.filter(sh=>sh.obs.length).sort((a,b)=>a.dateMs-b.dateMs);
  if(!sheetShifts.length) sheetShifts=[shifts[shifts.length-1]||{obs:[],division:"",locationName:"",dateMs:0}];
  const used={};
  const sheets=sheetShifts.map(sh=>{
    const dateStr=dateSlash(sh.dateMs);
    const tail=[sh.division,sh.locationName].filter(Boolean).join(", ");
    const title=`${dateStr} Weather Observations`+(tail?` - ${tail}`:"");
    const div=(sh.division||"").trim();
    const abbr=/^division /i.test(div)?"Div "+div.slice(9):div;
    let base=(abbr||"Obs")+" - "+dateCode(sh.dateMs);
    base=base.replace(/[:\\/?*\[\]]/g," "); if(base.length>31)base=base.slice(0,31); if(!base)base="Sheet";
    const cnt=(used[base]||0)+1; used[base]=cnt;
    let name=base;
    if(cnt>1){ const suf=" ("+cnt+")"; const room=Math.max(0,31-suf.length); name=(base.length>room?base.slice(0,room):base)+suf; }
    const rows=sh.obs.slice().sort((a,b)=>a.min-b.min);
    let sd=`<row r="1">${strC("A1",title)}</row><row r="2">`;
    headers.forEach((h,i)=>sd+=strC(col(i)+"2",h)); sd+="</row>";
    rows.forEach((o,ri)=>{ const R=ri+3;
      let c=`<c r="A${R}" s="1"><v>${o.min/1440}</v></c>`+numC("B"+R,o.temp)+numC("D"+R,o.rh);
      if(o.wind.high>0||o.wind.gust>0) c+=strC("E"+R,windImet(o.wind));
      c+=numC("F"+R,o.pigU)+numC("G"+R,o.pigS);
      if(o.elevationFeet!=null) c+=numC("H"+R,o.elevationFeet);
      c+=strC("I"+R,DIRNAME[o.aspect]||o.aspect);
      if(coordLat&&coordLon) c+=strC("J"+R,`${coordLat}, ${coordLon}`);
      if(o.note) c+=strC("K"+R,o.note);
      sd+=`<row r="${R}">${c}</row>`;
    });
    const footRow=rows.length+4;
    sd+=`<row r="${footRow}">${strC("A"+footRow,disclaimer)}</row>`;
    return {name, xml:H+`<worksheet xmlns="${ns}"><dimension ref="A1:K${footRow}"/><sheetData>${sd}</sheetData></worksheet>`};
  });

  const N=sheets.length;
  let ctOv="",sheetsX="",wbRels="";
  for(let i=1;i<=N;i++){
    ctOv+=`<Override PartName="/xl/worksheets/sheet${i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`;
    sheetsX+=`<sheet name="${esc(sheets[i-1].name)}" sheetId="${i}" r:id="rId${i}"/>`;
    wbRels+=`<Relationship Id="rId${i}" Type="${rel}/worksheet" Target="worksheets/sheet${i}.xml"/>`;
  }
  wbRels+=`<Relationship Id="rId${N+1}" Type="${rel}/styles" Target="styles.xml"/>`;
  const parts=[
    {path:"[Content_Types].xml",bytes:enc.encode(H+`<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${ctOv}</Types>`)},
    {path:"_rels/.rels",bytes:enc.encode(H+`<Relationships xmlns="${pkg}"><Relationship Id="rId1" Type="${rel}/officeDocument" Target="xl/workbook.xml"/></Relationships>`)},
    {path:"xl/workbook.xml",bytes:enc.encode(H+`<workbook xmlns="${ns}" xmlns:r="${rel}"><sheets>${sheetsX}</sheets></workbook>`)},
    {path:"xl/_rels/workbook.xml.rels",bytes:enc.encode(H+`<Relationships xmlns="${pkg}">${wbRels}</Relationships>`)},
    {path:"xl/styles.xml",bytes:enc.encode(H+`<styleSheet xmlns="${ns}"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="20" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`)},
  ];
  for(let i=0;i<N;i++) parts.push({path:`xl/worksheets/sheet${i+1}.xml`,bytes:enc.encode(sheets[i].xml)});
  return zipStore(parts);
}

//====================== Node export (conformance harness) ======================
// In the browser these top-level declarations are shared with app.js via the
// global lexical scope; in Node, require("./engine.js") returns this object.
const BadwaterEngine={
  REF_GRID,refTempRow,refRhCol,referenceFM,
  CORR,ASPECTS,DELTAS,correction,
  PIG_U,PIG_S,pigTempRow,pigFfmCol,pig,
  BEHAV,CAUTION,behavior,
  monthGroup,MONTHS,groupMonths,TIMEBANDS,timeBandFromClock,
  INHG_HPA,esat,psychro,BANDS,bandByNum,bandForElev,
  DIRNAME,DIRS,windRendered,windSpot,windSpoken,windImet,
  estimate,hhmm,grouped,dateCode,dateSlash,
  broadcastScript,delta,
  crc32,zipStore,buildXlsx,
};
if(typeof module!=="undefined"&&module.exports){ module.exports=BadwaterEngine; }
