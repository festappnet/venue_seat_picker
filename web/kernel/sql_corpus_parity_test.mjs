import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const [kernelPath,corpusPath,scenesPath]=process.argv.slice(2);
if(!kernelPath||!corpusPath||!scenesPath)throw Error('Usage: node sql_corpus_parity_test.mjs kernel.js sql-corpus.json dart-scenes.json');
const scope={console,setTimeout,clearTimeout};scope.self=scope;scope.window=scope;
vm.createContext(scope);vm.runInContext(readFileSync(kernelPath,'utf8'),scope);
const kernel=scope.VenueLayoutKernel,corpus=JSON.parse(readFileSync(corpusPath,'utf8')),expected=JSON.parse(readFileSync(scenesPath,'utf8'));
assert.equal(kernel.protocol,1);
for(const [name,fixture] of Object.entries(corpus)) {
 const document=JSON.stringify(fixture.document),resources=JSON.stringify(fixture.resources);
 assert.deepEqual(JSON.parse(kernel.validate(document)),[],`${name}: document`);
 assert.deepEqual(JSON.parse(kernel.validateResources(resources)),[],`${name}: resources`);
 assert.deepEqual(JSON.parse(kernel.decode(document)),expected[name].document,`${name}: normalized document matches Dart VM`);
 assert.deepEqual(JSON.parse(kernel.compileScene(document,resources,'{}')),expected[name].scene,`${name}: complete scene`);
}
console.log(`SQL / Dart VM / compiled JS: ${Object.keys(corpus).length} complete scenes match exactly.`);
