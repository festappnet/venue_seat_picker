import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
const fixture=JSON.parse(await readFile(new URL('./fixtures/canonical_rendering.json',import.meta.url),'utf8'));
const root=resolve(new URL('..',import.meta.url).pathname);
let browser,server,base;
before(async()=>{
 server=createServer(async(req,res)=>{
  if(req.url==='/fixture'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><style>body{margin:0}</style><script src="/dist/venue_layout_kernel.js"></script>');return;}
  try{res.setHeader('Content-Type','text/javascript');res.end(await readFile(join(root,new URL(req.url,'http://localhost').pathname)));}
  catch{res.statusCode=404;res.end();}
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${server.address().port}`;
 browser=await chromium.launch({headless:true});
});
after(async()=>{await browser?.close();await new Promise(resolve=>server.close(resolve));});
test('canonical prepared paragraphs paint exact paths and clips through camera and style updates',async()=>{
 const page=await browser.newPage({viewport:{width:1400,height:900}});
 await page.route('**/*',route=>route.request().url().startsWith(base)?route.continue():route.abort());
 try{
  await page.goto(`${base}/fixture`);
  await page.evaluate(async fixture=>{
   const {mount}=await import('/src/index.js'),host=document.createElement('div');document.body.append(host);
   window.viewer=mount(host,fixture);viewer.svg.style.cssText='width:1400px;height:800px;display:block';viewer.update({});
  },fixture);
  const inspect=()=>page.evaluate(()=>{
   const glyphs=viewer.scene.items.filter(item=>item.kind==='glyphs');
   const vectorId=viewer.options.document.nodes.find(node=>node.kind==='vector')?.id;
   return {issues:viewer.scene.issues,
    vectorExpected:viewer.scene.items.filter(item=>item.kind==='vectorPath').map(item=>item.path.map(command=>command.join(' ')).join(' ')),
    vectorActual:[...viewer.svg.querySelectorAll(`[data-node-id="${vectorId}"]`)].map(group=>group.querySelector(':scope > path')?.getAttribute('d')).filter(Boolean),
    gradients:viewer.svg.querySelectorAll('linearGradient').length,rawTextElements:viewer.svg.querySelectorAll('text').length,
    paths:glyphs.map(item=>{
    const group=[...viewer.svg.querySelectorAll(`[data-node-id="${item.nodeId}"]`)].find(node=>node.querySelector(':scope > defs > clipPath > rect'));
    return {expected:item.path.map(command=>command.join(' ')).join(' '),actual:group?.querySelector(':scope > path')?.getAttribute('d'),
     expectedClip:item.localClip,clip:group?.querySelector('clipPath rect')?Object.fromEntries(['x','y','width','height'].map(key=>[key,Number(group.querySelector('clipPath rect').getAttribute(key))])):null,
     stroke:Number(group?.querySelector(':scope > path')?.getAttribute('stroke-width')),matrix:group?.getAttribute('transform'),expectedMatrix:`matrix(${item.matrix.join(' ')})`};
   })};
  });
  for(let pass=0;pass<3;pass++){
   const result=await inspect();assert.deepEqual(result.issues,[]);assert.equal(result.paths.length,5);assert.deepEqual(result.vectorActual,result.vectorExpected);assert.equal(result.vectorExpected.length,2);assert.ok(result.gradients>0);assert.equal(result.rawTextElements,0);
   for(const path of result.paths){assert.equal(path.actual,path.expected);assert.deepEqual(path.clip,path.expectedClip);assert.equal(path.stroke,0);assert.equal(path.matrix,path.expectedMatrix);}
   await page.evaluate(pass=>{viewer.camera={x:pass*10,y:0,width:1400,height:800};viewer.update({});},pass);
  }
 }finally{await page.close();}
});
test('vector state remains balanced when culled and restored with opacity and clips',async()=>{
 const page=await browser.newPage({viewport:{width:1400,height:900}});
 try{
  await page.goto(`${base}/fixture`);
  await page.evaluate(async()=>{
   const {mount}=await import('/src/index.js'),host=document.createElement('div');document.body.append(host);
   const path=[['M',0,0],['L',100,0],['L',100,80],['L',0,80],['Z']];
   const vector={id:'20000000-0000-4000-8000-000000000090',kind:'vector',width:200,height:160,transform:{x:400,y:300,rotation:23},graphic:{type:'vector',version:1,width:100,height:80,commands:[
    {op:'layer',opacity:.5},{op:'clip',path,fillRule:'nonzero'},
    {op:'path',path,fillRule:'evenodd',fill:'#FF0000FF',stroke:'#000000FF',strokeWidth:2,strokeCap:'round',strokeJoin:'round',miterLimit:4},
    {op:'restore'},{op:'restore'},
   ]}};
   window.viewer=mount(host,{document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:1400,height:800,fill:'#FFFFFFFF'},textPolicy:{language:'und',direction:'auto'},styles:{},seatingDefaults:{},nodes:[vector]}});
   viewer.svg.style.cssText='width:1400px;height:800px;display:block';viewer.update({});
  });
  const state=()=>page.evaluate(()=>({issues:viewer.scene.issues,path:viewer.svg.querySelector('path[fill="#FF0000FF"]')?.getAttribute('fill-rule'),layers:viewer.svg.querySelectorAll('g[opacity="0.5"]').length,clips:viewer.svg.querySelectorAll('clipPath').length}));
  const initial=await state();assert.deepEqual(initial.issues,[]);assert.equal(initial.layers,1);assert.ok(initial.clips>=1);assert.equal(initial.path,'evenodd');
  await page.evaluate(()=>{viewer.camera={x:900,y:0,width:350,height:200};viewer.update({});});
  assert.equal((await state()).layers,0);
  await page.evaluate(()=>{viewer.camera={x:0,y:0,width:1400,height:800};viewer.update({});});
  assert.deepEqual(await state(),initial);
 }finally{await page.close();}
});
