import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {normalizeTitle,validateNote,validateLocalDate,validateRequest,validateChanges} from '../src/validation.mjs';
export const operation = (extra={}) => ({operationId:randomUUID(),localSequence:1,entityType:'task',entityId:randomUUID(),kind:'create',changes:{title:'Личная задача'},dependsOn:[],createdAt:'2026-10-19T10:00:00.000Z',...extra});
export const request = (operations=[]) => ({protocolVersion:1,deviceId:randomUUID(),cursor:0,operations});
test('titles trim and count Unicode code points',()=>{
 assert.equal(normalizeTitle('  Купить молоко 🥛  '),'Купить молоко 🥛');
 assert.equal([...normalizeTitle('😀'.repeat(500))].length,500);
 assert.throws(()=>normalizeTitle('😀'.repeat(501)),{code:'title_too_long'});
 assert.throws(()=>normalizeTitle(' \n '),{code:'title_empty'});
 assert.throws(()=>normalizeTitle(null),{code:'invalid_type'});
});
test('notes and real calendar dates enforce boundaries',()=>{
 assert.equal(validateNote('😀'.repeat(10000)).length,20000);
 assert.throws(()=>validateNote('x'.repeat(10001)),{code:'note_too_long'});
 for(const date of ['2026-02-30','2026-13-01','2026-2-01','2026-04-31']) assert.throws(()=>validateLocalDate(date),{code:'invalid_date'});
 assert.equal(validateLocalDate('2028-02-29'),'2028-02-29');
});
test('envelope rejects unknown fields, bad ids, versions and limits',()=>{
 assert.deepEqual(validateRequest(request()).operations,[]);
 for(const [body,code] of [[{...request(),cursor:-1},'invalid_cursor'],[{...request(),extra:1},'unknown_field'],[{...request(),protocolVersion:2},'protocol_mismatch'],[request(Array.from({length:101},()=>operation())),'too_many_operations'],[{...request(),deviceId:'abc'},'invalid_uuid']]) assert.throws(()=>validateRequest(body),{code});
});
test('invalid operations are isolated from a valid envelope',()=>{
 const body=request([operation({kind:'nonsense'})]);
 assert.equal(validateRequest(body).operations.length,1);
 assert.throws(()=>validateChanges(body.operations[0]),{code:'invalid_kind'});
 assert.throws(()=>validateChanges(operation({changes:{title:'ok',revision:8}})),{code:'unknown_field'});
});
test('recurrence rejects invalid weekday and month day',()=>{
 for(const weekdays of [[0],[8],[]]) assert.throws(()=>validateChanges(operation({entityType:'rule',changes:{frequency:'weekly',weekdays,timezone:'Europe/Moscow'}})),{code:'invalid_weekdays'});
 assert.throws(()=>validateChanges(operation({entityType:'rule',changes:{frequency:'monthly',monthDay:32,timezone:'Europe/Moscow'}})),{code:'invalid_month_day'});
});
test('UTC timestamps from Dart retain microsecond precision',()=>{assert.deepEqual(validateChanges(operation({createdAt:'2026-10-19T10:00:00.123456Z'})),{title:'Личная задача'});});
