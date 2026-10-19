import {DatabaseSync,backup} from 'node:sqlite';
import {randomUUID} from 'node:crypto';
export function openStore(filename,{workspaceId=randomUUID(),clock=()=>new Date().toISOString()}={}){
 const db=new DatabaseSync(filename,{timeout:5000});
 db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
 CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT;
 CREATE TABLE IF NOT EXISTS entities(type TEXT NOT NULL,id TEXT NOT NULL,value TEXT NOT NULL,revision INTEGER NOT NULL,PRIMARY KEY(type,id)) STRICT;
 CREATE TABLE IF NOT EXISTS changes(revision INTEGER PRIMARY KEY AUTOINCREMENT,type TEXT NOT NULL,id TEXT NOT NULL,value TEXT NOT NULL) STRICT;
 CREATE TABLE IF NOT EXISTS acknowledgements(operationId TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT;`);
 db.prepare('INSERT OR IGNORE INTO meta VALUES (?,?)').run('workspaceId',workspaceId);
 let closed=false;
 const store={
  workspaceId:db.prepare('SELECT value FROM meta WHERE key=?').get('workspaceId').value,clock,
  transaction(fn){db.exec('BEGIN IMMEDIATE');try{const result=fn();if(result&&typeof result.then==='function')throw Error('transaction must be synchronous');db.exec('COMMIT');return result;}catch(e){db.exec('ROLLBACK');throw e;}},
  getEntity(type,id){const row=db.prepare('SELECT value,revision FROM entities WHERE type=? AND id=?').get(type,id);return row?{...JSON.parse(row.value),revision:row.revision}:null;},
  putEntity(type,id,value){const clean={...value,id};delete clean.revision;const json=JSON.stringify(clean);const revision=Number(db.prepare('INSERT INTO changes(type,id,value) VALUES (?,?,?)').run(type,id,json).lastInsertRowid);db.prepare('INSERT INTO entities VALUES (?,?,?,?) ON CONFLICT(type,id) DO UPDATE SET value=excluded.value,revision=excluded.revision').run(type,id,json,revision);return revision;},
  listEntities(type){return db.prepare('SELECT value,revision FROM entities WHERE type=? ORDER BY id').all(type).map(row=>({...JSON.parse(row.value),revision:row.revision}));},
  getAcknowledgement(id){const row=db.prepare('SELECT value FROM acknowledgements WHERE operationId=?').get(id);return row?JSON.parse(row.value):null;},
  putAcknowledgement(ack){db.prepare('INSERT INTO acknowledgements VALUES (?,?)').run(ack.operationId,JSON.stringify(ack));},
  changesAfter(cursor,limit=500,byteBudget=8*1024*1024){
   const rows=db.prepare('SELECT * FROM changes WHERE revision>? ORDER BY revision LIMIT ?').all(cursor,limit+1);
   const changes=[];let bytes=0;
   for(const r of rows.slice(0,limit)){
    const change={entityType:r.type,entityId:r.id,revision:r.revision,value:{...JSON.parse(r.value),revision:r.revision}};
    const size=Buffer.byteLength(JSON.stringify(change))+1;
    if(changes.length&&bytes+size>byteBudget)break;
    changes.push(change);bytes+=size;
   }
   return {changes,nextCursor:changes.at(-1)?.revision??cursor,hasMore:rows.length>changes.length};
  },
  backupTo(path){return backup(db,path);},
  close(){if(!closed){db.close();closed=true;}}
 };
 return store;
}
