import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,join,extname} from 'node:path';
let browser,server,base;
const root=resolve(new URL('..',import.meta.url).pathname);
before(async()=>{server=createServer(async(req,res)=>{if(req.url==='/fixture'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><style>body{margin:0}</style><script src="/dist/venue_layout_kernel.js"></script>');return;}try{const p=join(root,new URL(req.url,'http://localhost').pathname);res.setHeader('Content-Type',({'.js':'text/javascript','.json':'application/json'}[extname(p)]||'application/octet-stream'));res.end(await readFile(p));}catch{res.statusCode=404;res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));base=`http://127.0.0.1:${server.address().port}`;browser=await chromium.launch({headless:true});});
after(async()=>{await browser?.close();await new Promise(r=>server.close(r));});
const left='00000000-0000-4000-8000-000000000001',right='00000000-0000-4000-8000-000000000002';
test('pan keeps chairs visible in the actual SVG viewport outside the nominal viewBox',async()=>{
 const p=await browser.newPage({viewport:{width:1300,height:800}});await p.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());try{
 await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
 await p.evaluate(async({left,right})=>{const{mount}=await import('/src/index.js');const host=document.createElement('div');host.style.cssText='width:1200px;height:600px';document.body.append(host);const node=(id,x)=>({id,kind:'seat',label:'',transform:{x,y:300,rotation:0},width:40,height:40});window.viewer=mount(host,{document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:1600,height:1200,fill:'#ffffffff'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[node(left,300),node(right,600)],selectionUnits:[],sections:[],attachments:[],presets:[]},onSelectionRequested:async()=>({accepted:true})});viewer.svg.style.cssText='width:1200px;height:600px;display:block';viewer.camera={x:0,y:0,width:800,height:600};viewer.update({});},{left,right});
 assert.equal(await p.locator(`svg [data-node-id="${left}"]`).count(),1);
 await p.mouse.move(800,500);await p.mouse.down();await p.mouse.move(600,500,{steps:3});await p.mouse.up();
 const visibility=await p.evaluate(left=>{const svg=viewer.svg,point=new DOMPoint(300,300).matrixTransform(svg.getScreenCTM()),box=svg.getBoundingClientRect();return{camera:viewer.camera,centerInsideActualViewport:point.x>box.left&&point.x<box.right&&point.y>box.top&&point.y<box.bottom,painted:!!svg.querySelector(`[data-node-id="${left}"]`)};},left);
 assert.equal(await p.locator(`svg [data-node-id="${right}"]`).count(),1,'Right chair stays visible while left one disappears');
 assert.equal(visibility.centerInsideActualViewport,true,'Left chair is physically inside the visible SVG, not beyond the browser clip');assert.equal(visibility.painted,true,`Visible left chair was culled: ${JSON.stringify(visibility)}`);
 }finally{await p.close();}
});

test('tall viewport and resize retain visible chairs after pointer pan',async()=>{
 const p=await browser.newPage({viewport:{width:1400,height:1400}});await p.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());try{
 await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
 await p.evaluate(async({left,right})=>{const{mount}=await import('/src/index.js');const host=document.createElement('div');document.body.append(host);const node=(id,x)=>({id,kind:'seat',label:'',transform:{x,y:300,rotation:0},width:40,height:40});window.viewer=mount(host,{document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:1600,height:1200,fill:'#ffffffff'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[node(left,300),node(right,600)],selectionUnits:[],sections:[],attachments:[],presets:[]}});viewer.svg.style.cssText='width:600px;height:1200px;display:block';viewer.camera={x:0,y:0,width:800,height:600};viewer.update({});},{left,right});
 await p.mouse.move(500,800);await p.mouse.down();await p.mouse.move(500,500,{steps:3});await p.mouse.up();
 assert.equal(await p.locator(`svg [data-node-id="${left}"]`).count(),1,'Tall meet viewport exposes the chair above nominal viewBox');
 await p.evaluate(()=>{viewer.camera={x:400,y:0,width:800,height:600};viewer.svg.style.cssText='width:800px;height:600px;display:block';viewer.update({});});
 await p.waitForFunction(left=>!viewer.svg.querySelector(`[data-node-id="${left}"]`),left);
 await p.evaluate(()=>{viewer.svg.style.width='1200px';});
 await p.waitForFunction(left=>!!viewer.svg.querySelector(`[data-node-id="${left}"]`),left,{timeout:2000});
 assert.equal(await p.locator(`svg [data-node-id="${left}"]`).count(),1,'Resize alone reveals newly visible chair without a data patch');
 }finally{await p.close();}
});

test('decorative chair families retain canonical DOM paint order through pan zoom and partial patches',async()=>{
 const p=await browser.newPage({viewport:{width:1300,height:900}});await p.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());try{
 await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
 for(const style of ['minimal','wood','lounge']){
 await p.evaluate(async({style,left,right})=>{window.viewer?.dispose();const{mount}=await import('/src/index.js');const host=document.createElement('div');document.body.append(host);const node=(id,kind,x,y,extra={})=>({id,kind,label:'',transform:{x,y,rotation:0},width:40,height:40,...extra});const c=document.createElement('canvas');c.width=c.height=1;c.getContext('2d').fillRect(0,0,1,1);const data=c.toDataURL('image/png').split(',')[1];const layout={schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:800,height:600,fill:'#ffffffff'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[node(left,'seat',300,300,{style:{material:style}}),node(right,'seat',600,300,{style:{material:style}}),node('00000000-0000-4000-8000-000000000003','table',450,300,{width:200,height:200,surface:{type:'circle'},style:{material:'wood'}}),node('00000000-0000-4000-8000-000000000004','shape',400,380,{width:600,height:40,shape:'polyline',style:{stroke:'#334155ff',strokeWidth:2},points:Array.from({length:13},(_,i)=>[-300+i*50,i%2?20:-20])})],selectionUnits:[],sections:[],attachments:[],presets:[]};window.viewer=mount(host,{document:layout});viewer.svg.style.cssText='width:1200px;height:600px;display:block';viewer.update({});},{style,left,right});
 const assertPainted=async()=>{const diff=await p.evaluate(()=>{const svg=viewer.svg,matrix=svg.getScreenCTM(),inverse=matrix.inverse(),rect=svg.getBoundingClientRect(),corners=[[rect.left,rect.top],[rect.right,rect.top],[rect.left,rect.bottom],[rect.right,rect.bottom]].map(([x,y])=>new DOMPoint(x,y).matrixTransform(inverse)),xs=corners.map(p=>p.x),ys=corners.map(p=>p.y),v={left:Math.min(...xs),right:Math.max(...xs),top:Math.min(...ys),bottom:Math.max(...ys)},zoom=Math.hypot(matrix.a,matrix.b);const scene=JSON.parse(VenueLayoutKernel.compileScene(JSON.stringify(viewer.options.document),JSON.stringify(viewer.options.resources||{protocol:2,fontFamilies:{},textLayouts:{},assets:{}}),JSON.stringify(viewer.options.seatPresentation||{})));const expected=scene.items.filter(i=>zoom>=(i.minZoom||0)&&(!i.bounds||(i.bounds.x+i.bounds.width>=v.left&&i.bounds.x<=v.right&&i.bounds.y+i.bounds.height>=v.top&&i.bounds.y<=v.bottom))).map(i=>({id:i.nodeId||i.id,path:i.kind==='image'?null:i.path.map(c=>c.join(' ')).join(' ')}));const actual=[...svg.children].filter(n=>n.tagName.toLowerCase()==='g').map(n=>({id:n.dataset.nodeId,path:n.querySelector(':scope > path')?.getAttribute('d')??null}));return{expected,actual,issues:scene.issues};});assert.deepEqual(diff.issues,[]);assert.deepEqual(diff.actual,diff.expected,`${style}: actual SVG children must match every visible canonical item in order`);};
 await assertPainted();await p.mouse.move(800,500);await p.mouse.down();await p.mouse.move(400,500,{steps:3});await p.mouse.up();await assertPainted();
 for(let i=0;i<4;i++){await p.evaluate(({left,i})=>viewer.update({seatPresentation:{[left]:{selected:i%2===0,status:i%2?'occupied':'available'}}}),{left,i});await assertPainted();await p.mouse.move(500,300);await p.mouse.wheel(0,i%2?80:-80);await p.waitForTimeout(25);await assertPainted();}
 }
 }finally{await p.close();}
});

test('wheel pinch and pan stay near whole-canvas fit across resize',async()=>{
 const p=await browser.newPage({viewport:{width:1400,height:1000},hasTouch:true});await p.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());try{
 await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
 await p.evaluate(async()=>{const{mount}=await import('/src/index.js');const host=document.createElement('div');document.body.append(host);window.viewer=mount(host,{document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:800,height:600,fill:'#ffffffff'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[],selectionUnits:[],sections:[],attachments:[],presets:[]}});viewer.svg.style.cssText='width:1200px;height:600px;display:block';viewer.update({});});
 await p.mouse.move(600,300);const anchor=await p.evaluate(()=>{const p=new DOMPoint(600,300).matrixTransform(viewer.svg.getScreenCTM().inverse());return{x:p.x,y:p.y};});await p.mouse.wheel(0,-250);await p.waitForTimeout(25);const afterAnchor=await p.evaluate(()=>{const p=new DOMPoint(600,300).matrixTransform(viewer.svg.getScreenCTM().inverse());return{x:p.x,y:p.y};});assert.ok(Math.hypot(anchor.x-afterAnchor.x,anchor.y-afterAnchor.y)<.001,'Wheel preserves pointer anchor away from camera limits');
 const shiftWidth=await p.evaluate(()=>viewer.camera.width);await p.keyboard.down('Shift');await p.mouse.wheel(0,50);await p.keyboard.up('Shift');await p.waitForTimeout(25);assert.ok(Math.abs((await p.evaluate(()=>viewer.camera.width))-shiftWidth)<.001,'Shift wheel pans without changing zoom');
 for(let i=0;i<8;i++)await p.mouse.wheel(0,2000);await p.waitForTimeout(30);
 const width=await p.evaluate(()=>viewer.camera.width);assert.ok(width<=800/.9+1e-6,`Infinite zoom-out made camera width ${width}`);
 await p.mouse.wheel(0,-693);await p.waitForTimeout(25);assert.ok(await p.evaluate(()=>viewer.camera.width<600),'Pinch starts from a zoomed-in plan');
 const cdp=await p.context().newCDPSession(p);await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:300,y:300,id:1},{x:900,y:300,id:2}]});await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:599,y:300,id:1},{x:601,y:300,id:2}]});await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 assert.ok(await p.evaluate(()=>viewer.camera.width>800&&viewer.camera.width<=800/.9+1e-6),'Native pinch really zooms out and stops at canvas fit');
 await p.mouse.move(600,300);await p.mouse.down();await p.mouse.move(-3000,300,{steps:3});await p.mouse.up();
 const contained=()=>p.evaluate(()=>{const m=viewer.svg.getScreenCTM(),a=new DOMPoint(0,0).matrixTransform(m),b=new DOMPoint(800,600).matrixTransform(m),r=viewer.svg.getBoundingClientRect();return Math.min(b.x,r.right)-Math.max(a.x,r.left)>=Math.min(b.x-a.x,r.width)/2-.1&&Math.min(b.y,r.bottom)-Math.max(a.y,r.top)>=Math.min(b.y-a.y,r.height)/2-.1;});assert.equal(await contained(),true,'Huge pan retains half of the smaller canvas/viewport on each axis');
 await p.evaluate(()=>{viewer.svg.style.cssText='width:360px;height:700px;display:block';});await p.waitForTimeout(50);assert.equal(await contained(),true,'Resize retains a useful fitted canvas');
 }finally{await p.close();}
});

test('wheel response matches the Flutter editor and keeps the cursor anchor', async () => {
 const p=await browser.newPage({viewport:{width:1200,height:900}});
 try {
  await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
  await p.evaluate(async()=>{
   const {mount}=await import('/src/index.js');
   const host=document.createElement('div');host.style.cssText='width:1200px;height:900px';document.body.append(host);
   window.viewer=mount(host,{document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:800,height:600,fill:'#ffffffff'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[],selectionUnits:[],sections:[],attachments:[],presets:[]}});
   viewer.svg.style.cssText='width:1200px;height:900px;display:block';viewer.update({});
  });
  const result=await p.evaluate(()=>{
   const svg=viewer.svg, point=new DOMPoint(450,300).matrixTransform(svg.getScreenCTM().inverse()), initial=viewer.camera.width;
   svg.dispatchEvent(new WheelEvent('wheel',{deltaY:-100,clientX:450,clientY:300,bubbles:true,cancelable:true}));
   const anchor=point.matrixTransform(svg.getScreenCTM()), ratio=viewer.camera.width/initial;
   svg.dispatchEvent(new WheelEvent('wheel',{deltaY:100,clientX:450,clientY:300,bubbles:true,cancelable:true}));
   return {ratio,anchor:{x:anchor.x,y:anchor.y},restored:viewer.camera.width/initial};
  });
  assert.ok(Math.abs(result.ratio-Math.exp(-100/200))<1e-9,`Wheel zoom must use the editor's 200-pixel exponential scale: ${JSON.stringify(result)}`);
  assert.ok(Math.hypot(result.anchor.x-450,result.anchor.y-300)<.01,'Zoom must retain the world point under the cursor');
  assert.ok(Math.abs(result.restored-1)<1e-9,'Opposite wheel deltas must restore the initial scale');
 } finally {await p.close();}
});

test('real pointer hover shows supplied tooltip on an unavailable seat and cleans up safely',async()=>{
 const p=await browser.newPage({viewport:{width:700,height:500}});
 await p.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());
 try{
  await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
  await p.evaluate(async id=>{
   const{mount}=await import('/src/index.js');const host=document.createElement('div');
   host.style.cssText='width:600px;height:400px';document.body.append(host);
   window.viewer=mount(host,{document:{schemaVersion:2,symbolSetVersion:1,
    canvas:{x:0,y:0,width:800,height:600,fill:'#ffffffff'},
    textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},
    nodes:[{id,kind:'seat',label:'',transform:{x:400,y:300,rotation:0},width:60,height:60}],
    selectionUnits:[],sections:[],attachments:[],presets:[]},
    seatPresentation:{[id]:{status:'occupied',selectable:false,tooltip:'<img src=x> A1 - 700 Kč'}}});
   viewer.svg.style.cssText='width:600px;height:400px;display:block';viewer.update({});
  },left);
  const point=await p.evaluate(()=>{const p=new DOMPoint(400,300).matrixTransform(viewer.svg.getScreenCTM());return{x:p.x,y:p.y};});
  const tip=p.locator('.venue-layout-tooltip[role=tooltip]');
  await p.mouse.move(point.x,point.y);await tip.waitFor({state:'visible',timeout:2000});
  assert.equal(await tip.textContent(),'<img src=x> A1 - 700 Kč');
  assert.equal(await tip.locator('img').count(),0,'Host text must not become markup');
  const box=await tip.boundingBox();assert.ok(box.x>=0&&box.y>=0&&box.x+box.width<=700&&box.y+box.height<=500);
  await p.evaluate(id=>viewer.update({seatPresentation:{[id]:{status:'occupied',selectable:false,tooltip:'A1 - 800 Kč'}}}),left);
  assert.equal(await tip.isVisible(),false,'A presentation patch must not leave stale hover text');
  await p.mouse.move(point.x+1,point.y+1);await tip.waitFor({state:'visible',timeout:2000});
  assert.equal(await tip.textContent(),'A1 - 800 Kč');
  await p.keyboard.press('Escape');assert.equal(await tip.isVisible(),false);
  await p.mouse.move(650,450);await p.mouse.move(point.x,point.y);await tip.waitFor({state:'visible',timeout:2000});
  await p.evaluate(()=>viewer.dispose());assert.equal(await tip.count(),0);
 }finally{await p.close();}
});


test('portrait can pan on spare axes while retaining half-visible bounds',async()=>{
 const p=await browser.newPage({viewport:{width:2100,height:1000}});
 try{
  await p.goto(`${base}/fixture`);await p.waitForFunction(()=>!!window.VenueLayoutKernel);
  await p.evaluate(async()=>{const {mount}=await import('/src/index.js');const host=document.createElement('div');host.style.cssText='width:2000px;height:900px';document.body.append(host);window.viewer=mount(host,{minZoom:1,maxZoom:8,canvasCornerRadius:12,document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:1920,height:3456,fill:'#ffffffff'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[],selectionUnits:[],sections:[],attachments:[],presets:[]}});viewer.svg.style.cssText='width:2000px;height:900px;display:block';viewer.update({});});
  const bounds=()=>p.evaluate(()=>{const s=viewer.svg,m=s.getScreenCTM(),r=s.getBoundingClientRect(),a=new DOMPoint(0,0).matrixTransform(m),b=new DOMPoint(1920,3456).matrixTransform(m);return {left:a.x,right:b.x,top:a.y,bottom:b.y,viewport:{left:r.left,right:r.right,top:r.top,bottom:r.bottom},clip:s.style.clipPath};});
  const visible=(b)=>{for(const axis of ['x','y']){const [start,end,extent]=axis==='x'?['left','right','width']:['top','bottom','height'];const overlap=Math.min(b[end],b.viewport[end])-Math.max(b[start],b.viewport[start]);const minimum=Math.min(b[end]-b[start],(b.viewport[end]-b.viewport[start]))/2;assert.ok(overlap>=minimum-.1,`Half visible ${axis}: ${JSON.stringify(b)}`);}};

  for(const x of [1900,100]){const before=await bounds();const sx=(Math.max(before.left,before.viewport.left)+Math.min(before.right,before.viewport.right))/2,sy=(Math.max(before.top,before.viewport.top)+Math.min(before.bottom,before.viewport.bottom))/2;await p.mouse.move(sx,sy);await p.mouse.down();await p.mouse.move(x,850,{steps:3});await p.mouse.up();const b=await bounds();visible(b);assert.ok(Math.abs(b.left-before.left)>1,'Fitted plan can pan instead of snapping to center');assert.match(b.clip,/round 12px/);}
  await p.evaluate(()=>viewer.zoomBy(2));
  await p.mouse.move(1000,450);await p.mouse.down();await p.mouse.move(1900,850,{steps:3});await p.mouse.up();
  let b=await bounds();visible(b);
  await p.setViewportSize({width:420,height:1000});await p.evaluate(()=>{viewer.svg.style.width='360px';viewer.fitToScreen();});
  await p.mouse.move(180,450);await p.mouse.down();await p.mouse.move(400,850,{steps:3});await p.mouse.up();b=await bounds();visible(b);
 }finally{await p.close();}
});
