import {v5} from 'uuid';
import {Temporal} from '@js-temporal/polyfill';
import {validateLocalDate,fail} from './validation.mjs';
export const successorId=(ruleId,occurrenceDate)=>v5(occurrenceDate,ruleId);
export function nextReminderAt(rule,date){
 if(!rule.reminderTime)return null;
 const [year,month,day]=date.split('-').map(Number),[hour,minute]=rule.reminderTime.split(':').map(Number);
 return new Date(Temporal.ZonedDateTime.from({timeZone:rule.timezone,year,month,day,hour,minute},{disambiguation:'compatible'}).epochMilliseconds).toISOString();
}
export function nextOccurrence(rule,dueDate,completionDate){
 validateLocalDate(completionDate);if(dueDate)validateLocalDate(dueDate);
 const base=dueDate&&dueDate>completionDate?dueDate:completionDate;
 const date=new Date(base+'T00:00:00Z');
 if(rule.frequency==='monthly'){
  for(let offset=0;offset<3;offset++){
   const first=new Date(Date.UTC(date.getUTCFullYear(),date.getUTCMonth()+offset,1));
   const last=new Date(Date.UTC(first.getUTCFullYear(),first.getUTCMonth()+1,0)).getUTCDate();
   first.setUTCDate(Math.min(rule.monthDay,last));const result=first.toISOString().slice(0,10);if(result>base)return result;
  }
 }
 if(rule.frequency==='daily'||rule.frequency==='weekly'){
  for(let i=1;i<=7;i++){date.setUTCDate(date.getUTCDate()+1);if(rule.frequency==='daily'||rule.weekdays.includes(date.getUTCDay()||7))return date.toISOString().slice(0,10);}
 }
 fail('invalid_recurrence','rule');
}
