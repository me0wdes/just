import {test} from 'node:test';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';import {once} from 'node:events';import {randomBytes,createHash} from 'node:crypto';import {mkdirSync,writeFileSync} from 'node:fs';import {join} from 'node:path';import {temporaryStore,request,operation} from './helpers.mjs';
test('CLI restarts with durable tasks and acknowledgement without logging secrets',async t=>{
 const {directory,cleanup}=temporaryStore();t.after(cleanup);const token=randomBytes(32).toString('base64url');let child;
 t.after(()=>child?.kill());
 async function start(){child=spawn(process.execPath,['src/index.mjs','--data',directory,'--port','0'],{cwd:new URL('../',import.meta.url),env:{...process.env,DAY_SYNC_TOKEN:token},windowsHide:true});let output='';const url=await new Promise((resolve,reject)=>{child.stdout.on('data',chunk=>{output+=chunk;const match=output.match(/http:\/\/127\.0\.0\.1:\d+/);if(match)resolve(match[0]);});child.on('error',reject);child.on('exit',code=>reject(Error('CLI exited '+code)));});assert.equal(output.includes(token),false);return url;}
 const op=operation();const body=request([op]);
 async function send(url){const response=await fetch(url+'/sync',{method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},body:JSON.stringify(body)});assert.equal(response.status,200);return response.json();}
 const first=await send(await start());assert.equal(first.acknowledgements[0].status,'applied');child.kill();await once(child,'exit');const second=await send(await start());assert.equal(second.workspaceId,first.workspaceId);assert.equal(second.acknowledgements[0].status,'duplicate');assert.ok(second.changes.some(x=>x.value.title==='Личная задача'));child.kill();await once(child,'exit');child=null;
});
test('CLI serves each person from users/<name> and keeps their tasks apart',async t=>{
 const {directory,cleanup}=temporaryStore();const owner=randomBytes(32).toString('base64url'),mama=randomBytes(32).toString('base64url');
 mkdirSync(join(directory,'users','mama'),{recursive:true});writeFileSync(join(directory,'users','mama','key.sha256'),createHash('sha256').update(mama).digest('hex')+'\n');
 mkdirSync(join(directory,'users','broken'));writeFileSync(join(directory,'users','broken','key.sha256'),'not a hash');
 const child=spawn(process.execPath,['src/index.mjs','--data',directory,'--port','0'],{cwd:new URL('../',import.meta.url),env:{...process.env,DAY_SYNC_TOKEN:owner},windowsHide:true});
 t.after(async()=>{child.kill();await once(child,'exit');cleanup();});
 const url=await new Promise((resolve,reject)=>{let output='';child.stdout.on('data',chunk=>{output+=chunk;const match=output.match(/http:\/\/127\.0\.0\.1:\d+/);if(match)resolve(match[0]+'/sync');});child.on('exit',code=>reject(Error('CLI exited '+code)));});
 const send=async(key,operations=[])=>{const response=await fetch(url,{method:'POST',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify(request(operations))});return {status:response.status,body:await response.json()};};
 const mine=await send(owner,[operation({changes:{title:'Задача владельца'}})]);assert.equal(mine.status,200);
 const hers=await send(mama);assert.equal(hers.status,200);assert.notEqual(hers.body.workspaceId,mine.body.workspaceId);assert.equal(hers.body.changes.some(x=>x.entityType==='task'),false);
 await send(mama,[operation({changes:{title:'Задача мамы'}})]);
 const titles=async key=>(await send(key)).body.changes.filter(x=>x.entityType==='task').map(x=>x.value.title);
 assert.deepEqual(await titles(owner),['Задача владельца']);assert.deepEqual(await titles(mama),['Задача мамы']);
 assert.equal((await send('not a hash')).status,401);
});
