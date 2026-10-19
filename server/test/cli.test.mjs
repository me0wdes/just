import {test} from 'node:test';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';import {once} from 'node:events';import {randomBytes} from 'node:crypto';import {temporaryStore,request,operation} from './helpers.mjs';
test('CLI restarts with durable tasks and acknowledgement without logging secrets',async t=>{
 const {directory,cleanup}=temporaryStore();t.after(cleanup);const token=randomBytes(32).toString('base64url');let child;
 t.after(()=>child?.kill());
 async function start(){child=spawn(process.execPath,['src/index.mjs','--data',directory,'--port','0'],{cwd:new URL('../',import.meta.url),env:{...process.env,DAY_SYNC_TOKEN:token},windowsHide:true});let output='';const url=await new Promise((resolve,reject)=>{child.stdout.on('data',chunk=>{output+=chunk;const match=output.match(/http:\/\/127\.0\.0\.1:\d+/);if(match)resolve(match[0]);});child.on('error',reject);child.on('exit',code=>reject(Error('CLI exited '+code)));});assert.equal(output.includes(token),false);return url;}
 const op=operation();const body=request([op]);
 async function send(url){const response=await fetch(url+'/sync',{method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},body:JSON.stringify(body)});assert.equal(response.status,200);return response.json();}
 const first=await send(await start());assert.equal(first.acknowledgements[0].status,'applied');child.kill();await once(child,'exit');const second=await send(await start());assert.equal(second.workspaceId,first.workspaceId);assert.equal(second.acknowledgements[0].status,'duplicate');assert.ok(second.changes.some(x=>x.value.title==='Личная задача'));child.kill();await once(child,'exit');child=null;
});
