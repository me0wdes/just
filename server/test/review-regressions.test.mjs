import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {temporaryStore,request,operation} from './helpers.mjs';
import {applySync} from '../src/sync.mjs';

test('workspace mismatch rejects before any entity or acknowledgement mutation',t=>{
 const {store,cleanup}=temporaryStore();t.after(cleanup);
 const op=operation();
 assert.throws(()=>applySync(store,{...request([op]),expectedWorkspaceId:randomUUID()}),e=>e.code==='workspace_mismatch');
 assert.equal(store.getEntity('task',op.entityId),null);
 assert.equal(store.getAcknowledgement(op.operationId),null);
 assert.equal(store.changesAfter(0).changes.length,0);
});

test('maximum Unicode records page below transport limit and advance without loss',t=>{
 const {store,cleanup}=temporaryStore();t.after(cleanup);
 store.transaction(()=>{for(let i=0;i<500;i++)store.putEntity('task',randomUUID(),{title:`Дело ${i}`,note:'😀'.repeat(10000)});});
 let cursor=0, seen=0;
 for(let i=0;i<20;i++){
  const page=applySync(store,{...request(),cursor});
  assert.ok(Buffer.byteLength(JSON.stringify(page))<16*1024*1024);
  assert.ok(page.nextCursor>cursor);cursor=page.nextCursor;seen+=page.changes.length;
  if(!page.hasMore)break;
 }
 assert.equal(seen,501);assert.equal(cursor,501);
});
