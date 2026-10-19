import {createServer} from 'node:http';import {createHash,timingSafeEqual} from 'node:crypto';
import {applySync} from './sync.mjs';import {ValidationError} from './validation.mjs';
const MAX_BYTES=262144;
export function createHttpServer({store,tokenHash,logger=()=>{}}){
 if(!Buffer.isBuffer(tokenHash)||tokenHash.length!==32)throw Error('tokenHash must be SHA256');
 return createServer({requestTimeout:15000,headersTimeout:10000,maxHeaderSize:8192},async(req,res)=>{
  const reply=(status,body)=>{if(res.destroyed)return;res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'});res.end(JSON.stringify(body));try{logger({event:'request',status});}catch{}};
  const error=(status,code)=>reply(status,{error:{code}});
  if(req.method!=='POST'||req.url!=='/sync'){req.resume();return error(404,'not_found');}
  const auth=req.headers.authorization??'';const supplied=auth.startsWith('Bearer ')?auth.slice(7):'';
  if(!timingSafeEqual(createHash('sha256').update(supplied).digest(),tokenHash)){req.resume();return error(401,'unauthorized');}
  if(!/^application\/json(?:;|$)/i.test(req.headers['content-type']??'')){req.resume();return error(400,'content_type');}
  if(Number(req.headers['content-length'])>MAX_BYTES){req.resume();return error(413,'body_too_large');}
  try{
   let bytes=0;const chunks=[];
   for await(const chunk of req){bytes+=chunk.length;if(bytes>MAX_BYTES){error(413,'body_too_large');return;}chunks.push(chunk);}
   let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return error(400,'invalid_json');}
   reply(200,applySync(store,body));
  }catch(e){if(req.aborted||res.destroyed)return;if(e instanceof ValidationError)return error(['protocol_mismatch','workspace_mismatch'].includes(e.code)?409:400,e.code);error(500,'internal_error');}
 });
}
