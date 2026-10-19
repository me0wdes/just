import {randomUUID} from 'node:crypto';
import {INBOX_ID,validateRequest,validateChanges,ValidationError,fail} from './validation.mjs';
import {nextOccurrence,successorId,nextReminderAt} from './recurrence.mjs';
const defaults={task:{note:'',listId:INBOX_ID,dueDate:null,reminderAtUtc:null,reminderTimezone:null,plannedForDate:null,completedAt:null,completionId:null,successorId:null,recurrenceRuleId:null,occurrenceDate:null,position:0,deletedAt:null},list:{color:'#8C9B7A',position:0,deletedAt:null},rule:{active:true,reminderTime:null,deletedAt:null}};
function prepareReferences(store,type,value){
 if(type!=='task')return value;
 if(value.listId!==INBOX_ID){const list=store.getEntity('list',value.listId);if(!list||list.deletedAt)value.listId=INBOX_ID;}
 // Lists are labels: drop references to lists that are gone.
 if(Array.isArray(value.listIds))value.listIds=value.listIds.filter(id=>{const list=store.getEntity('list',id);return list&&!list.deletedAt;});
 if(value.recurrenceRuleId){const rule=store.getEntity('rule',value.recurrenceRuleId);if(!rule||rule.deletedAt)fail('rule_missing','recurrenceRuleId');}
 return value;
}
function applyOperation(store,op,changes){
 const {entityType:type,entityId:id,kind}=op;const current=store.getEntity(type,id);const now=store.clock();
 if(type==='list'&&id===INBOX_ID)fail('inbox_immutable','entityId');
 if(kind==='create'){
  if(current)fail(current.deletedAt?'entity_deleted':'entity_exists','entityId');
  const value=prepareReferences(store,type,{...defaults[type],...changes,id});store.putEntity(type,id,value);return;
 }
 if(kind==='restore'){
  const snapshot=changes.snapshot;if(!current&&!snapshot)fail('entity_missing','entityId');
  if(snapshot?.id&&snapshot.id!==id)fail('entity_id_mismatch','snapshot.id');
  const value=prepareReferences(store,type,snapshot?{...defaults[type],...snapshot,id}:{...current,deletedAt:null});store.putEntity(type,id,value);return;
 }
 if(!current)fail('entity_missing','entityId');
 if(kind==='delete'){
  if(!current.deletedAt)store.putEntity(type,id,{...current,deletedAt:now});
  if(type==='list')for(const task of store.listEntities('task'))if(task.listId===id||(task.listIds||[]).includes(id))store.putEntity('task',task.id,{...task,listId:task.listId===id?INBOX_ID:task.listId,listIds:(task.listIds||[]).filter(x=>x!==id)});
  return;
 }
 if(current.deletedAt)fail('entity_deleted','entityId');
 if(kind==='patch'){store.putEntity(type,id,prepareReferences(store,type,{...current,...changes}));return;}
 if(kind==='complete'){
  if(current.completedAt)return {completionId:current.completionId,successorId:current.successorId??null};
  const completionId=randomUUID();let nextId=null,childRevision=null;
  const rule=current.recurrenceRuleId?store.getEntity('rule',current.recurrenceRuleId):null;
  if(rule&&!rule.deletedAt&&rule.active){
   const date=nextOccurrence(rule,current.dueDate,changes.completionDate);nextId=successorId(rule.id,date);
   const child=store.getEntity('task',nextId);
   if(child&&!child.deletedAt)fail('successor_exists','successorId');
   childRevision=store.putEntity('task',nextId,{...defaults.task,title:current.title,note:current.note,listId:current.listId,listIds:current.listIds??[],position:current.position+1024,recurrenceRuleId:rule.id,dueDate:date,occurrenceDate:date,reminderAtUtc:nextReminderAt(rule,date),reminderTimezone:rule.reminderTime?rule.timezone:null});
  }
  store.putEntity('task',id,{...current,completedAt:now,completionId,successorId:nextId,successorCreatedRevision:childRevision});
  return {completionId,successorId:nextId};
 }
 if(kind==='undoComplete'){
  if(!current.completedAt||current.completionId!==changes.completionId)fail('completion_mismatch','completionId');
  if(current.successorId){const child=store.getEntity('task',current.successorId);if(!child||child.revision!==current.successorCreatedRevision)fail('successor_modified','successorId');store.putEntity('task',child.id,{...child,deletedAt:now});}
  store.putEntity('task',id,{...current,completedAt:null,completionId:null,successorId:null,successorCreatedRevision:null});
 }
}
export function applySync(store,body){
 const request=validateRequest(body);
 if(request.expectedWorkspaceId!==undefined&&request.expectedWorkspaceId!==store.workspaceId)fail('workspace_mismatch','expectedWorkspaceId');
 return store.transaction(()=>{
  if(!store.getEntity('list',INBOX_ID))store.putEntity('list',INBOX_ID,{id:INBOX_ID,name:'Входящие',color:'#8C9B7A',position:0,deletedAt:null});
  const acknowledgements=[];
  for(const op of request.operations){
   const prior=store.getAcknowledgement(op.operationId);
   if(prior){acknowledgements.push(prior.status==='rejected'?prior:{...prior,status:'duplicate'});continue;}
   let ack;
   try{
    const changes=validateChanges(op);
    for(const dependency of op.dependsOn){const accepted=store.getAcknowledgement(dependency);if(!accepted||accepted.status==='rejected')fail('dependency_rejected','dependsOn');}
    const effect=applyOperation(store,op,changes);ack={operationId:op.operationId,status:'applied',...(effect?{effect}:{})};
   }catch(e){if(!(e instanceof ValidationError))throw e;ack={operationId:op.operationId,status:'rejected',code:e.code};}
   store.putAcknowledgement(ack);acknowledgements.push(ack);
  }
  return {protocolVersion:1,workspaceId:store.workspaceId,acknowledgements,...store.changesAfter(request.cursor,500)};
 });
}
