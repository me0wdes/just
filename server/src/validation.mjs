export const INBOX_ID='00000000-0000-4000-8000-000000000001';
export class ValidationError extends Error {
 constructor(code,field=''){super(code);this.code=code;this.field=field;}
}
export function fail(code,field=''){throw new ValidationError(code,field);}
const object=(v,field)=>{if(!v || typeof v!=='object'||Array.isArray(v))fail('invalid_type',field);return v;};
const fields=(v,allowed,field='')=>{object(v,field);for(const k of Object.keys(v))if(!allowed.includes(k))fail('unknown_field',field?`${field}.${k}`:k);};
export function uuid(v,field='id'){if(typeof v!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v))fail('invalid_uuid',field);return v;}
export function normalizeTitle(v){if(typeof v!=='string')fail('invalid_type','title');v=v.trim();if(!v)fail('title_empty','title');if([...v].length>500)fail('title_too_long','title');return v;}
export function validateNote(v){if(typeof v!=='string')fail('invalid_type','note');if([...v].length>10000)fail('note_too_long','note');return v;}
export function validateLocalDate(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(v)||v<'0001-01-01'||!Number.isFinite(Date.parse(v+'T00:00:00Z'))||new Date(v+'T00:00:00Z').toISOString().slice(0,10)!==v)fail('invalid_date','date');return v;}
function timestamp(v,field){if(typeof v!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/.test(v)||!Number.isFinite(Date.parse(v)))fail('invalid_timestamp',field);validateLocalDate(v.slice(0,10));return v;}
function zone(v){if(typeof v!=='string')fail('invalid_timezone','timezone');try{new Intl.DateTimeFormat('en',{timeZone:v});}catch{fail('invalid_timezone','timezone');}return v;}
const taskFields=['title','note','listId','listIds','dueDate','reminderAtUtc','reminderTimezone','plannedForDate','position','recurrenceRuleId'];
const ruleFields=['frequency','weekdays','monthDay','timezone','reminderTime','active'];
const listFields=['name','color','icon','position'];
export function validateEntity(type,value,{snapshot=false,partial=false}={}){
 const allowed=type==='task'?taskFields:type==='list'?listFields:type==='rule'?ruleFields:null;
 if(!allowed)fail('invalid_entity_type','entityType');
 fields(value,[...allowed,...(snapshot?['id','completedAt','completionId','successorId','occurrenceDate','deletedAt']:[])]);
 const out={...value};
 for(const [k,v] of Object.entries(value)){
  if(k==='title'||k==='name')out[k]=normalizeTitle(v);
  else if(k==='note')out[k]=validateNote(v);
  else if(['dueDate','plannedForDate','occurrenceDate'].includes(k)&&v!==null)validateLocalDate(v);
  else if(k==='listIds'){if(!Array.isArray(v)||v.length>50||new Set(v).size!==v.length)fail('invalid_list_ids',k);v.forEach(id=>uuid(id,k));}
  else if(['listId','recurrenceRuleId','completionId','successorId','id'].includes(k)&&v!==null)uuid(v,k);
  else if(['reminderAtUtc','completedAt','deletedAt'].includes(k)&&v!==null)timestamp(v,k);
  else if(['timezone','reminderTimezone'].includes(k)&&v!==null)zone(v);
  else if(k==='position'&&(!Number.isFinite(v)||Math.abs(v)>Number.MAX_SAFE_INTEGER))fail('invalid_position',k);
  else if(k==='icon'&&(typeof v!=='string'||!/^[a-z]{1,20}$/.test(v)))fail('invalid_icon',k);
  else if(k==='color'&&(typeof v!=='string'||!/^#[0-9a-f]{6}$/i.test(v)))fail('invalid_color',k);
  else if(k==='frequency'&&!['daily','weekly','monthly'].includes(v))fail('invalid_frequency',k);
  else if(k==='weekdays'&&(!Array.isArray(v)||v.length<1||v.length>7||v.some(d=>!Number.isInteger(d)||d<1||d>7)||new Set(v).size!==v.length))fail('invalid_weekdays',k);
  else if(k==='monthDay'&&(!Number.isInteger(v)||v<1||v>31))fail('invalid_month_day',k);
  else if(k==='active'&&typeof v!=='boolean')fail('invalid_type',k);
  else if(k==='reminderTime'&&v!==null&&(typeof v!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(v)))fail('invalid_time',k);
 }
 if(!partial){
  if(type==='task'&&!('title'in out))fail('title_empty','title');
  if(type==='list'&&!('name'in out))fail('title_empty','name');
  if(type==='rule'){
   if(!out.frequency)fail('invalid_frequency','frequency');zone(out.timezone);
   if(out.frequency==='weekly'&&!out.weekdays)fail('invalid_weekdays','weekdays');
   if(out.frequency==='monthly'&&!out.monthDay)fail('invalid_month_day','monthDay');
  }
 }
 return out;
}
export function validateChanges(op){
 fields(op,['operationId','localSequence','entityType','entityId','kind','changes','dependsOn','createdAt']);
 uuid(op.operationId,'operationId');uuid(op.entityId,'entityId');
 if(!Number.isSafeInteger(op.localSequence)||op.localSequence<1)fail('invalid_sequence','localSequence');
 if(!['task','list','rule'].includes(op.entityType))fail('invalid_entity_type','entityType');
 if(!['create','patch','delete','restore','complete','undoComplete'].includes(op.kind))fail('invalid_kind','kind');
 if(!Array.isArray(op.dependsOn)||op.dependsOn.length>100)fail('invalid_dependencies','dependsOn');op.dependsOn.forEach(d=>uuid(d,'dependsOn'));timestamp(op.createdAt,'createdAt');
 if(op.kind==='complete'){if(op.entityType!=='task')fail('invalid_kind','kind');fields(op.changes,['completionDate']);validateLocalDate(op.changes.completionDate);return op.changes;}
 if(op.kind==='undoComplete'){if(op.entityType!=='task')fail('invalid_kind','kind');fields(op.changes,['completionId']);uuid(op.changes.completionId,'completionId');return op.changes;}
 if(op.kind==='delete'){fields(op.changes,[]);return {};}
 if(op.kind==='restore'){
  fields(op.changes,['snapshot']);return op.changes.snapshot?{snapshot:validateEntity(op.entityType,op.changes.snapshot,{snapshot:true})}:{};
 }
 return validateEntity(op.entityType,op.changes,{partial:op.kind==='patch'});
}
export function validateRequest(v){
 fields(v,['protocolVersion','deviceId','cursor','operations','expectedWorkspaceId']);
 if(v.expectedWorkspaceId!==undefined)uuid(v.expectedWorkspaceId,'expectedWorkspaceId');
 if(v.protocolVersion!==1)fail('protocol_mismatch','protocolVersion');uuid(v.deviceId,'deviceId');
 if(!Number.isSafeInteger(v.cursor)||v.cursor<0)fail('invalid_cursor','cursor');
 if(!Array.isArray(v.operations))fail('invalid_type','operations');if(v.operations.length>100)fail('too_many_operations','operations');
 // Invalid operation payloads are rejected individually by the sync transaction.
 for(const op of v.operations){object(op,'operations');uuid(op.operationId,'operationId');}
 return v;
}


