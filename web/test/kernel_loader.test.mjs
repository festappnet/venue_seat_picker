import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
let browser,server,base,loads=0;
const raster=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC','base64');
const rasterHash=createHash('sha256').update(raster).digest('hex');
const root=resolve(new URL('..',import.meta.url).pathname);
const geometry=JSON.parse(await readFile(new URL('./fixtures/canonical_rendering.json',import.meta.url),'utf8')).document;
before(async()=>{
 server=createServer(async(req,res)=>{
  const path=new URL(req.url,'http://localhost').pathname;
  if(path==='/blank'){res.setHeader('Content-Type','text/html');res.end('<!doctype html>');return;}
  if(path==='/raster.png'){res.setHeader('Content-Type','image/png');res.end(raster);return;}
  if(path==='/bad.js'){res.setHeader('Content-Type','text/javascript');res.end('globalThis.VenueLayoutKernel={protocol:99};');return;}
  if(path==='/dist/venue_layout_kernel.js')loads++;
  try{res.setHeader('Content-Type','text/javascript');res.end(await readFile(join(root,path)));}
  catch{res.statusCode=404;res.end();}
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));base=`http://127.0.0.1:${server.address().port}`;
 browser=await chromium.launch({headless:true});
});
test('processed raster verifies actual bytes and decoded dimensions before synchronous rendering',async()=>{
 const page=await browser.newPage();try{
  await page.goto(`${base}/blank`);
  const result=await page.evaluate(async({hash,length})=>{
   const {loadLayoutAssets}=await import('/src/assets.js');
   if (Object.keys(await loadLayoutAssets({})).length) throw Error('Empty resources must remain protocol neutral');
   const ref=`image:${hash}`,asset={hash,url:'/raster.png',width:2,height:2,mimeType:'image/png',byteLength:length};
   const resources=await loadLayoutAssets({assets:{[ref]:asset}});
   const errors=[];
   for(const changed of [{width:3},{hash:'0'.repeat(64)},{byteLength:length-1}]){
    const candidate={...asset,...changed};
    try{await loadLayoutAssets({assets:{[`image:${candidate.hash}`]:candidate}});}
    catch(e){errors.push(e.message);}
   }
   const controller=new AbortController();controller.abort();
   try{await loadLayoutAssets({assets:{[ref]:asset}},{signal:controller.signal});}catch(e){errors.push(e.name);}
   return {resolved:resources.assets[ref].mimeType==='image/png'&&resources.assets[ref].url.startsWith('data:image/png;base64,'),errors};
  },{hash:rasterHash,length:raster.length});
  assert.deepEqual(result,{resolved:true,errors:['asset_dimensions_mismatch','asset_hash_mismatch','asset_size_limit','AbortError']});
 }finally{await page.close();}
});
after(async()=>{await browser?.close();await new Promise(r=>server.close(r));});
test('canonical kernel validates public wire geometry with one concurrent load',async()=>{
 const page=await browser.newPage();try{
  await page.goto(`${base}/blank`);const before=loads;
  const result=await page.evaluate(async geometry=>{
   const {loadKernel}=await import('/src/index.js');
   const first=loadKernel('/dist/venue_layout_kernel.js'),second=loadKernel(new URL('/dist/venue_layout_kernel.js',location.href));
   const same=first===second;await Promise.all([first,second]);
   await loadKernel('/already-loaded-no-second-request.js');
   return {same,issues:JSON.parse(VenueLayoutKernel.validate(JSON.stringify(geometry)))};
  },geometry);
  assert.deepEqual(result,{same:true,issues:[]});assert.equal(loads-before,1);
 }finally{await page.close();}
});
test('failed asset load rejects and permits retry, invalid protocol rejects explicitly',async()=>{
 const page=await browser.newPage();try{
  await page.goto(`${base}/blank`);
  const result=await page.evaluate(async()=>{
   const {loadKernel}=await import('/src/index.js');const failures=[];
   for(let i=0;i<2;i++)try{await loadKernel('/missing.js');}catch(e){failures.push(e.message);}
   await loadKernel('/dist/venue_layout_kernel.js');
   delete globalThis.VenueLayoutKernel;
   try{await loadKernel('/bad.js');}catch(e){failures.push(e.message);}
   try{await loadKernel('/dist/venue_layout_kernel.js');}catch(e){failures.push(e.message);}
   return failures;
  });
  assert.equal(result.length,4);assert.match(result[0],/could not be loaded/);assert.match(result[1],/could not be loaded/);
  assert.match(result[2],/protocol/);assert.match(result[3],/protocol/);
 }finally{await page.close();}
});
