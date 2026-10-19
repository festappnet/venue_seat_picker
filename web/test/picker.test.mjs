import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,join,extname} from 'node:path';
let browser,server,base;
const root=resolve(new URL('..',import.meta.url).pathname);
before(async()=>{server=createServer(async(req,res)=>{if(req.url==='/qa-blank'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><script src="/dist/venue_layout_kernel.js"></script>');return;}try{let p=join(root,new URL(req.url,'http://localhost').pathname);if(p.endsWith('/'))p+='index.html';res.setHeader('Content-Type',({'.js':'text/javascript','.json':'application/json','.html':'text/html'}[extname(p)]||'application/octet-stream'));res.end(await readFile(p));}catch{res.statusCode=404;res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));base=`http://127.0.0.1:${server.address().port}`;browser=await chromium.launch({headless:true});});
after(async()=>{await browser?.close();await new Promise(r=>server.close(r));});
const setup=async()=>{const page=await browser.newPage();await page.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());await page.goto(`${base}/qa-blank`);await page.waitForFunction(()=>!!globalThis.VenueLayoutKernel);await page.evaluate(async()=>{const {mount}=await import('/src/index.js');document.body.replaceChildren();const host=document.createElement('div');document.body.append(host);const node=(id,x)=>({id,kind:'seat',label:'',transform:{x,y:100,rotation:0},width:40,height:40});window.calls=[];window.resolveSelection={};window.viewer=mount(host,{document:{schemaVersion:1,symbolSetVersion:1,defaultTextStyle:{fontId:'fixture:sans',size:24,color:'#222222ff'},selectionUnits:[],sections:[],attachments:[],presets:[],generators:[],canvas:{x:0,y:0,width:800,height:600,fill:'#ffffffff'},nodes:[node('00000000-0000-4000-8000-000000000001',100),node('00000000-0000-4000-8000-000000000002',200)]},onSelectionRequested:(ids,selecting)=>new Promise(resolve=>{const id=[...ids][0];window.calls.push({ids:[...ids],selecting});window.resolveSelection[id]=resolve;})});});return page;};
const a='00000000-0000-4000-8000-000000000001',b='00000000-0000-4000-8000-000000000002';
test('independent late rejection preserves another accepted selection',async()=>{const p=await setup();try{await p.locator(`[data-node-id="${a}"]`).last().press('Space');await p.locator(`[data-node-id="${b}"]`).last().press('Space');await p.evaluate(b=>resolveSelection[b]({accepted:true}),b);await p.evaluate(a=>resolveSelection[a]({accepted:false,message:'Conflict'}),a);await p.waitForFunction(()=>viewer.pending.size===0);assert.deepEqual(await p.evaluate(()=>[...viewer.selected]),[b]);assert.equal(await p.locator(`[data-node-id="${b}"]`).last().getAttribute('aria-pressed'),'true');}finally{await p.close();}});
test('unavailable seat sends no selection request',async()=>{const p=await setup();try{await p.evaluate(a=>viewer.update({seatPresentation:{[a]:{status:'occupied'}}}),a);await p.locator(`[data-node-id="${a}"]`).last().press('Space');assert.deepEqual(await p.evaluate(()=>calls),[]);assert.match(await p.getByRole('status').textContent(),/unavailable/);}finally{await p.close();}});
test('state patch retains unchanged scene elements and camera',async()=>{const p=await setup();try{await p.evaluate(b=>{window.retained=viewer.svg.querySelector(`[data-node-id="${b}"]`);window.cameraBefore=viewer.svg.getAttribute('viewBox');},b);await p.evaluate(a=>viewer.update({seatPresentation:{[a]:{selected:true}}}),a);assert.equal(await p.evaluate(b=>retained===viewer.svg.querySelector(`[data-node-id="${b}"]`),b),true);assert.equal(await p.evaluate(()=>viewer.svg.getAttribute('viewBox')),await p.evaluate(()=>cameraBefore));}finally{await p.close();}});
test('paired-unit pending rejection is atomic and standing sends quantity only',async()=>{const p=await setup();try{
 await p.evaluate(({a,b})=>{const document={...viewer.options.document,selectionUnits:[{id:'00000000-0000-4000-8000-000000000009',nodeIds:[a,b]}],nodes:[...viewer.options.document.nodes,{id:'00000000-0000-4000-8000-000000000003',kind:'capacityArea',label:'Standing',transform:{x:400,y:300,rotation:0},width:160,height:100,capacity:20}]};viewer.update({document,capacityPresentation:{'00000000-0000-4000-8000-000000000003':{capacity:20,available:20}},onQuantityRequested:async(id,count)=>{window.quantity={id,count};return{accepted:true};}});},{a,b});
 await p.locator(`[data-node-id="${a}"]`).last().press('Space');assert.deepEqual(await p.evaluate(()=>calls[0].ids),[a,b]);assert.deepEqual(new Set(await p.evaluate(()=>[...viewer.pending])),new Set([a,b]));
 await p.evaluate(a=>resolveSelection[a]({accepted:false,message:'Unit unavailable'}),a);await p.waitForFunction(()=>viewer.pending.size===0);assert.deepEqual(await p.evaluate(()=>[...viewer.selected]),[]);
 await p.locator('[data-node-id="00000000-0000-4000-8000-000000000003"]').last().press('Space');await p.getByRole('spinbutton').fill('2');await p.getByRole('button',{name:'Confirm quantity'}).click();await p.waitForFunction(()=>!!window.quantity);assert.equal(await p.evaluate(()=>quantity.count),2);assert.equal(await p.evaluate(()=>calls.length),1);
}finally{await p.close();}});
test('public kernel rejects malformed transport documents and malformed font resources',async()=>{const p=await setup();try{
 const fixtureResources=JSON.parse(await readFile(new URL('../../assets/layout_fonts/fixtures.json',import.meta.url),'utf8'));
 const result=await p.evaluate(resources=>{const valid=structuredClone(viewer.options.document),cases=[];
 let bad=structuredClone(valid);bad.nodes[0].transform.x='100';cases.push(bad);
 bad=structuredClone(valid);bad.nodes.push(structuredClone(bad.nodes[0]));cases.push(bad);
 bad=structuredClone(valid);bad.nodes[0].parentId='00000000-0000-4000-8000-000000000099';cases.push(bad);
 bad=structuredClone(valid);bad.nodes[0].width=-1;cases.push(bad);
 bad=structuredClone(valid);bad.schemaVersion=2;cases.push(bad);
 return{documents:cases.map(d=>JSON.parse(VenueLayoutKernel.validate(JSON.stringify(d)))),validResources:JSON.parse(VenueLayoutKernel.validateResources(JSON.stringify(resources))),invalidResources:[{protocol:1,fonts:{bad:{unitsPerEm:1000,ascent:800,descent:-200,glyphs:{a:{advance:600,path:[['M',0]]}}}}},{protocol:2,fonts:{}}].map(r=>JSON.parse(VenueLayoutKernel.validateResources(JSON.stringify(r))))};},fixtureResources);
 assert.ok(result.documents.every(issues=>issues.length>0));assert.deepEqual(result.validResources,[]);assert.ok(result.invalidResources.every(issues=>issues.length>0));
}finally{await p.close();}});

test('actual JS file import rejects malformed draft before replacing live picker',async()=>{
 const p=await browser.newPage();await p.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());
 try{await p.goto(`${base}/demo/`);await p.waitForFunction(()=>!!window.venueDemo?.document);const before=await p.locator('#picker').innerHTML();
 await p.locator('#import').setInputFiles({name:'invalid.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({schemaVersion:1,nodes:[]}))});await p.locator('#status').filter({hasText:'Import rejected; current plan preserved'}).waitFor();assert.equal(await p.locator('#picker').innerHTML(),before);
 const previousStatus=await p.locator('#status').textContent();const document=await p.evaluate(()=>globalThis.venueDemoSeed.layout);const bytes=Buffer.from(JSON.stringify({protocol:1,fonts:{'fixture:sans':{id:'fixture:sans',hash:'a'.repeat(64),unitsPerEm:'invalid',ascent:800,descent:-200,glyphs:{}}}}));const invalidFont={format:'venue-layout-demo',version:1,protocol:1,layout:document,host:{},resources:[{path:'resources/fixtures.json',size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),data:bytes.toString('base64')}]};
 await p.locator('#import').setInputFiles({name:'invalid-font.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(invalidFont))});await p.waitForFunction(old=>document.getElementById('status').textContent!==old,previousStatus);assert.match(await p.locator('#status').textContent(),/Import rejected; current plan preserved/);assert.equal(await p.locator('#picker').innerHTML(),before);
 }finally{await p.close();}
});

test('presentation patches preserve atomic layer order in scene and SVG', async()=>{
 const p=await setup();
 const resources=JSON.parse(await readFile(new URL('../../assets/layout_fonts/fixtures.json',import.meta.url),'utf8'));
 try {
  const result=await p.evaluate(({resources,a,b})=>{
   const viewer=window.viewer, original=viewer.options.document;
   const back='00000000-0000-4000-8000-000000000010',front='00000000-0000-4000-8000-000000000011',caption='00000000-0000-4000-8000-000000000012';
   const group=(id,z)=>({id,kind:'group',z,transform:{x:0,y:0,rotation:0},width:40,height:40});
   const first={...original.nodes[0],parentId:back,label:'A',fontId:'fixture:sans',size:48};
   const label={...first,id:caption,kind:'text',z:1,label:'',text:'A'};
   const cover={...first,id:b,parentId:front,kind:'shape'};
   const document={...original,nodes:[group(back,0),first,label,group(front,1),cover]};
   viewer.update({document,resources,seatPresentation:{}});
   const capture=()=>({scene:viewer.scene.items.map(i=>({id:i.id,order:i.paintOrder,node:i.nodeId||i.id})),svg:[...viewer.svg.querySelectorAll('g[data-node-id]')].map(n=>n.dataset.nodeId)});
   const states=[capture()];
   for(const presentation of [{[a]:{selected:true}},{[b]:{status:'occupied'},[a]:{selected:true}},{[b]:{status:'occupied'},[a]:{selected:false}},{}]) {
    viewer.update({seatPresentation:presentation});
    const full=JSON.parse(VenueLayoutKernel.compileScene(JSON.stringify(document),JSON.stringify(resources),JSON.stringify(presentation)));
    states.push({...capture(),full:full.items.map(i=>({id:i.id,order:i.paintOrder,node:i.nodeId||i.id}))});
   }
   return states;
  },{resources,a,b});
  for(const state of result) {
   if(state.full) assert.deepEqual(state.scene,state.full);
   assert.deepEqual(state.svg,state.scene.map(i=>i.node));
   assert.equal(state.scene.at(-1).node,b);
  }
 } finally {await p.close();}
});
test('preselected seat releases visibly; pending blocks double clicks and rejection restores the check',async()=>{const p=await setup();try{
 await p.evaluate(a=>viewer.update({seatPresentation:{[a]:{selected:true,status:'available'}}}),a);
 await p.locator(`[data-node-id="${a}"]`).last().press('Space');
 assert.equal(await p.evaluate(()=>calls[0].selecting),false);
 assert.equal(await p.evaluate(a=>viewer.selected.has(a),a),false);
 assert.equal(await p.evaluate(a=>[...viewer.sceneItems.values()].some(i=>i.id===`${a}:state`&&i.stroke==='#FFFFFFFF'),a),false);
 await p.locator(`[data-node-id="${a}"]`).last().press('Space');assert.equal(await p.evaluate(()=>calls.length),1);
 await p.evaluate(a=>resolveSelection[a]({accepted:false}),a);await p.waitForFunction(()=>viewer.pending.size===0);
 assert.equal(await p.evaluate(a=>viewer.selected.has(a),a),true);
 assert.equal(await p.evaluate(a=>[...viewer.sceneItems.values()].some(i=>i.id===`${a}:state`&&i.stroke==='#FFFFFFFF'),a),true);
 await p.evaluate(b=>viewer.update({seatPresentation:{[b]:{selectable:false}}}),b);
 await p.locator(`[data-node-id="${b}"]`).last().press('Space');assert.equal(await p.evaluate(()=>calls.length),1);
}finally{await p.close();}});

test('SVG applies canonical outline width and opacity to each paint like Flutter', async()=>{
 const p=await setup();try{
  const result=await p.evaluate(()=>{
   const d=structuredClone(viewer.options.document);
   d.nodes[0]={...d.nodes[0],fill:'#FFFFFFFF',stroke:'#0000FFFF',strokeWidth:2,opacity:.5};
   d.nodes[1]={...d.nodes[1],fill:'#FFFFFFFF',stroke:'#0000FFFF',strokeWidth:0};
   viewer.update({document:d});
   return d.nodes.map(n=>{const g=viewer.svg.querySelector(`[data-node-id="${n.id}"]`),path=g.querySelector('path'),style=getComputedStyle(path);return{strokeWidth:Number(style.strokeWidth.replace('px','')),fillOpacity:Number(style.fillOpacity),strokeOpacity:Number(style.strokeOpacity),groupOpacity:Number(getComputedStyle(g).opacity)};});
  });
  assert.deepEqual(result,[{strokeWidth:2,fillOpacity:.5,strokeOpacity:.5,groupOpacity:1},{strokeWidth:0,fillOpacity:1,strokeOpacity:1,groupOpacity:1}]);
 }finally{await p.close();}
});

test('attached chairs face the table until explicitly rotated by the user',async()=>{
 const p=await setup();try{
  const result=await p.evaluate(()=>{
   const d=structuredClone(viewer.options.document),table='00000000-0000-4000-8000-000000000003';
   d.nodes=d.nodes.map((n,i)=>({...n,parentId:table,transform:{x:-150,y:i*80,rotation:270},manual:true,...i?{manualRotation:true}:{}}));
   d.nodes.push({id:table,kind:'table',shape:'circle',width:180,height:180,transform:{x:400,y:300,rotation:0}});
   viewer.update({document:d});
   const pose=id=>viewer.scene.items.find(i=>i.id===id).matrix;
   const auto=pose(d.nodes[0].id),manual=pose(d.nodes[1].id);
   d.nodes[0].transform.y=-80;d.nodes[1].transform.y=160;
   viewer.update({document:d});
   return {auto,manual,movedAuto:pose(d.nodes[0].id),movedManual:pose(d.nodes[1].id),issues:viewer.scene.issues};
  });
  assert.deepEqual(result.issues,[]);
  assert.deepEqual(result.auto.slice(0,4),[0,1,-1,0]);
  assert.deepEqual(result.manual.slice(0,4),[0,-1,1,0]);
  assert.deepEqual(result.movedManual.slice(0,4),result.manual.slice(0,4));
  const m=result.movedAuto,dx=m[4]-400,dy=m[5]-300;
  assert.ok((m[2]*dx+m[3]*dy)/Math.hypot(dx,dy)>.999,'Moved automatic backrest stays away from tabletop');
 }finally{await p.close();}
});

test('standing restores total quantity, accepts zero, and fences replaced async replies',async()=>{
 const p=await setup();try{
 const area='00000000-0000-4000-8000-000000000003';
 await p.evaluate(area=>{
  const document={...viewer.options.document,nodes:[...viewer.options.document.nodes,{id:area,kind:'capacityArea',label:'Standing',transform:{x:400,y:300,rotation:0},width:160,height:100}]};
  viewer.update({document,capacityPresentation:{[area]:{available:5,quantity:3}},onQuantityRequested:(id,count)=>new Promise(resolve=>{window.quantityCount=count;window.quantityResolve=resolve;})});
 },area);
 await p.locator(`[role=list] [data-node-id="${area}"]`).press('Space');
 assert.equal(await p.locator('input[type=number]').inputValue(),'3');
 await p.locator('input[type=number]').fill('0');await p.getByRole('button',{name:'Confirm quantity',exact:true}).click();
 assert.equal(await p.evaluate(()=>quantityCount),0);
 await p.evaluate(area=>viewer.update({capacityPresentation:{[area]:{available:5,quantity:3}}}),area);
 assert.equal(await p.evaluate(area=>viewer.pending.has(area),area),true);
 await p.evaluate(()=>quantityResolve({accepted:true}));await p.waitForFunction(()=>viewer.pending.size===0);
 await p.locator(`[role=list] [data-node-id="${area}"]`).press('Space');assert.equal(await p.locator('input[type=number]').inputValue(),'0');
 await p.getByRole('button',{name:'Confirm quantity',exact:true}).click();
 await p.evaluate(()=>{viewer.update({document:structuredClone(viewer.options.document)});quantityResolve({accepted:false,message:'stale quantity'});});
 await p.waitForFunction(()=>viewer.pending.size===0);
 assert.equal(await p.getByRole('status').textContent().then(t=>t.includes('stale quantity')),false);
 }finally{await p.close();}
});

test('host localized accessible labels and selection announcements use public messages', async()=>{
 const p=await setup();
 await p.evaluate(()=>viewer.update({messages:{place:'Místo',available:'Volné',selectedPlaces:'Vybraná místa: {count}'}}));
 assert.match(await p.getByRole('list').textContent(),/Volné/);
 await p.getByRole('list').getByRole('button').first().press('Space');
 await p.evaluate(a=>resolveSelection[a]({accepted:true}),a);
 await p.waitForFunction(()=>viewer.pending.size===0);
 assert.match(await p.getByRole('status').textContent(),/Vybraná místa:/);
 await p.close();
});

test('assistive seat list remains keyboard accessible without occupying visual space', async()=>{
 const p=await setup();
 try {
  const list=p.locator('.venue-layout-viewer > [role="list"]');
  const bounds=await list.boundingBox();
  assert.ok(bounds.width<=1 && bounds.height<=1, 'assistive seat buttons must not become a visible seat list');
  assert.equal(await list.getByRole('button').count(),2);
  await list.getByRole('button').first().focus();
  await p.keyboard.press('Space');
  assert.deepEqual(await p.evaluate(()=>calls.map(c=>c.ids[0])),[a]);
 } finally {await p.close();}
});
