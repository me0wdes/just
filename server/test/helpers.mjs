import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {openStore} from '../src/store.mjs';
export function temporaryStore(){const directory=mkdtempSync(join(tmpdir(),'day-test-'));const filename=join(directory,'sync.sqlite');const store=openStore(filename);return {store,filename,directory,cleanup(){try{store.close();}catch{}rmSync(directory,{recursive:true,force:true});}};}
export const operation=(extra={})=>({operationId:randomUUID(),localSequence:1,entityType:'task',entityId:randomUUID(),kind:'create',changes:{title:'Личная задача'},dependsOn:[],createdAt:'2026-10-19T10:00:00.000Z',...extra});
export const request=(operations=[])=>({protocolVersion:1,deviceId:randomUUID(),cursor:0,operations});
