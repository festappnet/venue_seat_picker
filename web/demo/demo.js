import { mount } from '../src/index.js';
let view, documentData, resources={}, prices={}, selected=new Set(), quantities={}, occupied=false, loadRequest=0, activeGeneration=0;
const el=id=>document.getElementById(id);
const previewToken=new URLSearchParams(location.search).get('editor');
const fromEditor=!!previewToken&&/^[a-f0-9-]{36}$/.test(previewToken);
if(fromEditor){
  document.documentElement.lang='cs';
  document.querySelector('h1').textContent='Vyberte si místa';
  document.title='Výběr míst - webový náhled';
  el('sample-label').textContent='Náhled vašeho rozpracovaného sálu';
  el('back-to-editor').hidden=false;
  el('back-to-editor').href=`/flutter/?fromPreview=${encodeURIComponent(previewToken)}`;
  el('import-tools').hidden=true;
  el('legend').hidden=false;
  el('reset').textContent='Zrušit výběr';
  el('status').textContent='Připravuji webový náhled…';
  el('preview-note').textContent='Ukázkový výběr - nevytváří rezervaci ani objednávku';
}
const status=message=>el('status').textContent=message;
const maxBytes=16*1024*1024;
async function digest(data){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',data))].map(b=>b.toString(16).padStart(2,'0')).join('');}
async function decode(text){
  if(new TextEncoder().encode(text).length>maxBytes)throw Error('Import exceeds 16 MiB');
  const value=JSON.parse(text);
  if(value.schemaVersion===2)return {layout:value,resources};
  if(Object.keys(value).some(k=>!['format','version','protocol','layout','host','resources'].includes(k)))throw Error('Unknown portable bundle field');
  if(value.format!=='venue-layout-demo'||value.version!==2||value.protocol!==1)throw Error('Unsupported file version');
  const loaded={};
  for(const item of value.resources){
    if(Object.keys(item).some(k=>!['path','size','sha256','data'].includes(k))||item.path!=='resources/fixtures.json')throw Error('Unknown portable resource');
    if(!/^resources\/[a-zA-Z0-9_-]+\.json$/.test(item.path)||loaded[item.path])throw Error('Invalid or duplicate resource path');
    const bytes=Uint8Array.from(atob(item.data),c=>c.charCodeAt(0));
    if(bytes.length>maxBytes||bytes.length!==item.size||await digest(bytes)!==item.sha256)throw Error('Resource integrity failed');
    loaded[item.path]=JSON.parse(new TextDecoder().decode(bytes));
  }
  if(!loaded['resources/fixtures.json'])throw Error('Missing bundled resources');
  const resources=loaded['resources/fixtures.json'];
  if(Object.keys(resources).some(k=>!['protocol','fontFamilies','fontFaces','textLayouts','numberSymbols','assets'].includes(k)))throw Error('Unknown portable resource field');
  if('assets' in resources&&(!resources.assets||typeof resources.assets!=='object'||Array.isArray(resources.assets)))throw Error('Embedded assets must be a map');
  for(const [id,asset] of Object.entries(resources.assets??{})){
    if(!id||!asset||typeof asset!=='object'||Array.isArray(asset)||Object.keys(asset).some(k=>!['hash','url','byteLength','mimeType','width','height'].includes(k)))throw Error('Invalid embedded asset fields');
    const prefix=`data:${asset.mimeType};base64,`;
    if(!['image/png','image/jpeg','image/webp'].includes(asset.mimeType)||typeof asset.url!=='string'||!asset.url.startsWith(prefix))throw Error('Embedded image required');
    const bytes=Uint8Array.from(atob(asset.url.slice(prefix.length)),c=>c.charCodeAt(0));
    if(bytes.length>800*1024||bytes.length!==asset.byteLength||await digest(bytes)!==asset.hash)throw Error('Embedded asset integrity failed');
  }
  return {layout:value.layout,resources,host:value.host||{}};
}
function price(n){return prices[n.id]??prices[n.parentId]??250;}
function capacityStates(){return Object.fromEntries(documentData.nodes.filter(n=>n.kind==='capacityArea').map(n=>[n.id,{capacity:n.capacity??20,available:n.capacity??20,selectedQuantity:quantities[n.id]??0}]));}
function presentation(){return Object.fromEntries(documentData.nodes.filter(n=>n.kind==='seat').map(n=>[n.id,{status:selected.has(n.id)?'selected':occupied?'occupied':'available',selected:selected.has(n.id),label:n.label||'Seat',accessibilityLabel:`${n.label||'Seat'} - ${price(n)} CZK`,price:price(n)}]));}
async function response(){
  const scenario=el('scenario').value;
  await new Promise(r=>setTimeout(r,scenario==='timeout'?800:100));
  if(scenario!=='success'){status(`Demo ${scenario}: selection preserved. Retry with success.`);return {accepted:false,message:`Demo ${scenario}`};}
  return {accepted:true};
}
function units(ids){const result=new Set(ids);for(const unit of documentData.selectionUnits??[]){if(unit.nodeIds.some(id=>result.has(id)))for(const id of unit.nodeIds)result.add(id);}return result;}
function update(){
  const standing=Object.values(quantities).reduce((a,b)=>a+b,0),total=documentData.nodes.filter(n=>selected.has(n.id)).reduce((sum,n)=>sum+price(n),0);
  el('selected').textContent=fromEditor?`Sezení: ${selected.size} · Stání: ${standing} · Cena sezení: ${total.toLocaleString('cs-CZ')} Kč`:`${selected.size} seats selected; ${standing} standing selected - sample seat total ${total} CZK`;
  view?.update({document:documentData,resources,seatPresentation:presentation(),capacityPresentation:capacityStates()});
}
function capacities(){
  el('capacity').replaceChildren();
  for(const area of documentData.nodes.filter(n=>n.kind==='capacityArea')){
    const label=document.createElement('label');label.textContent=`${area.label||'Standing'} - total capacity ${area.capacity}: `;
    const input=document.createElement('input');input.type='number';input.min='0';input.max=String(area.capacity);input.value=String(quantities[area.id]??0);
    input.setAttribute('aria-label',`${area.label||'Standing'} selected quantity`);
    input.onchange=async()=>{const count=Number(input.value);if(!Number.isInteger(count)||count<0||count>area.capacity){input.value=String(quantities[area.id]??0);return;}
      const result=await response();if(result.accepted)quantities[area.id]=count;else input.value=String(quantities[area.id]??0);update();};
    label.append(input);el('capacity').append(label);
  }
}
function validatePrices(values,layout){
  if(values==null)return;
  if(typeof values!=='object'||Array.isArray(values))throw Error('Invalid demo prices');
  const ids=new Set(layout.nodes.filter(n=>['seat','table','group','furniture','capacityArea'].includes(n.kind)).map(n=>n.id));
  for(const [id,value] of Object.entries(values))if(!ids.has(id)||!Number.isSafeInteger(value)||value<0||value>100000000)throw Error('Invalid or orphaned sample price binding');
}
async function load(text){
  const request=++loadRequest,parsed=await decode(text);
  const issues=JSON.parse(VenueLayoutKernel.validate(JSON.stringify(parsed.layout)));
  if(issues.length)throw Error(issues[0].reason);
  const resourceIssues=JSON.parse(VenueLayoutKernel.validateResources(JSON.stringify(parsed.resources)));
  if(resourceIssues.length)throw Error('Invalid font resource: '+resourceIssues[0].reason);
  const host=parsed.host||{},allowed=new Set(['prices','template','revision','label','savedBaseline','savedPrices']);
  if(Object.keys(host).some(k=>!allowed.has(k)))throw Error('Unknown demo metadata');
  validatePrices(host.prices,parsed.layout);
  if(host.savedBaseline){const errors=JSON.parse(VenueLayoutKernel.validate(JSON.stringify(host.savedBaseline)));if(errors.length)throw Error('Invalid saved baseline');validatePrices(host.savedPrices,host.savedBaseline);}
  for(const asset of Object.values(parsed.resources.assets??{})){
    const bytes=Uint8Array.from(atob(asset.url.split(',')[1]),c=>c.charCodeAt(0));
    const image=await createImageBitmap(new Blob([bytes],{type:asset.mimeType}));
    const valid=image.width===asset.width&&image.height===asset.height;image.close();if(!valid)throw Error('Embedded image dimensions differ');
  }
  if(parsed.layout.background&&!parsed.resources.assets?.[parsed.layout.background.assetRef])throw Error('Missing embedded background');
  const scene=JSON.parse(VenueLayoutKernel.compileScene(JSON.stringify(parsed.layout),JSON.stringify(parsed.resources),'{}'));
  if(scene.issues.length)throw Error('Missing or invalid prepared resource: '+scene.issues[0].reason);
  if(request!==loadRequest)return;
  const nextPrices=host.prices||{},nextPresentation=Object.fromEntries(parsed.layout.nodes.filter(n=>n.kind==='seat').map(n=>[n.id,{label:n.label||'Seat',status:'available'}]));
  const staging=document.createElement('div');let next;
  try{next=mount(staging,{document:parsed.layout,resources:parsed.resources,seatPresentation:nextPresentation,
    onQuantityRequested:async(id,count)=>{const result=await response();if(activeGeneration!==request)return{accepted:false,message:'Document changed'};if(result.accepted){quantities[id]=count;update();}return result;},
    onSelectionRequested:async(ids,selecting)=>{const result=await response();if(activeGeneration!==request)return{accepted:false,message:'Document changed'};if(result.accepted){for(const id of units(ids)){if(selecting)selected.add(id);else selected.delete(id);}update();}return result;}});
  }catch(error){next?.dispose();throw error;}
  if(fromEditor){
    const list=staging.querySelector('[role="list"]');
    if(list){
      const details=document.createElement('details'),summary=document.createElement('summary');
      summary.textContent='Přístupný seznam míst';
      list.before(details);details.append(summary,list);
    }
  }
  // Commit only a completely decoded, validated and mounted candidate.
  view?.dispose();el('picker').replaceChildren(...staging.childNodes);view=next;
  activeGeneration=request;documentData=parsed.layout;resources=parsed.resources;prices=nextPrices;selected=new Set();quantities={};
  capacities();update();status(fromEditor?'Vyberte místo kliknutím. Plánek můžete přibližovat a posouvat.':'Same exported geometry loaded. Select seats or standing quantities.');
}
el('import').onchange=async()=>{try{const file=el('import').files[0];if(file)await load(await file.text());}catch(error){status(`Import rejected; current plan preserved: ${error.message}`);}};
el('reset').onclick=()=>{selected.clear();quantities={};capacities();update();};
el('patch').onclick=()=>{occupied=!occupied;update();status('Presentation patch applied; geometry unchanged.');};
// Deterministic artifact harness uses the same public import path as a file import.
window.venueDemo={load,get document(){return documentData;},get selected(){return [...selected];}};

// Build-time seed comes from VenueLayoutTemplates public API, never a JS generator.
(async()=>{
 if(fromEditor){
  try{
   const text=await new Promise((resolve,reject)=>{
    const request=indexedDB.open('venue-layout-preview',1);
    request.onupgradeneeded=()=>request.result.createObjectStore('drafts');
    request.onerror=()=>reject(Error('Úložiště náhledu není dostupné.'));
    request.onblocked=()=>reject(Error('Úložiště náhledu je zablokované.'));
    request.onsuccess=()=>{
     const database=request.result;
     const transaction=database.transaction('drafts');
     const read=transaction.objectStore('drafts').get(previewToken);
     read.onsuccess=()=>resolve(read.result);
     read.onerror=()=>reject(Error('Plánek se nepodařilo načíst.'));
     transaction.oncomplete=()=>database.close();
     transaction.onabort=()=>{database.close();reject(Error('Načtení plánku bylo přerušeno.'));};
    };
   });
   if(typeof text!=='string')throw Error('Chybí plánek z editoru. Vraťte se a otevřete náhled znovu.');
   await load(text);
  }catch(error){status(`Náhled se nepodařilo otevřít: ${error.message}`);}
  return;
 }
 if(globalThis.venueDemoSeed) {
  const {layout,resources}=globalThis.venueDemoSeed;
  const bytes=new TextEncoder().encode(JSON.stringify(resources));
  let binary=""; for(let i=0;i<bytes.length;i+=8192) binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
  const data=btoa(binary);
  load(JSON.stringify({format:'venue-layout-demo',version:2,protocol:1,layout,host:{},resources:[{path:'resources/fixtures.json',size:bytes.length,sha256:await digest(bytes),data}]})).catch(error=>status(`Seed failed: ${error.message}`));
} })();
