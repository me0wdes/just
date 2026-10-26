import {createServer} from 'node:http';import {createServer as createTlsServer} from 'node:https';import {createHash} from 'node:crypto';
import {applySync} from './sync.mjs';import {ValidationError} from './validation.mjs';
const MAX_BYTES=262144;
// stores: SHA256 of a key (hex) -> that person's store. One key, one database, so nobody reaches another person's tasks.
// tls: {key, cert} serves HTTPS directly, for a server without a web proxy in front.
export function createHttpServer({store,tokenHash,stores,tls,logger=()=>{}}){
 if(!stores){if(!Buffer.isBuffer(tokenHash)||tokenHash.length!==32)throw Error('tokenHash must be SHA256');stores=new Map([[tokenHash.toString('hex'),store]]);}
 const options={requestTimeout:15000,headersTimeout:10000,maxHeaderSize:8192,...(tls??{})};
 return (tls?createTlsServer:createServer)(options,async(req,res)=>{
  const reply=(status,body)=>{if(res.destroyed)return;res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'});res.end(JSON.stringify(body));try{logger({event:'request',status});}catch{}};
  const error=(status,code)=>reply(status,{error:{code}});
  if(req.method!=='POST'||req.url!=='/sync'){req.resume();return error(404,'not_found');}
  const auth=req.headers.authorization??'';const supplied=auth.startsWith('Bearer ')?auth.slice(7):'';
  // Keys are 32 random bytes, so a lookup by their SHA256 gives timing nothing to guess.
  const userStore=stores.get(createHash('sha256').update(supplied).digest('hex'));
  if(!userStore){req.resume();return error(401,'unauthorized');}
  if(!/^application\/json(?:;|$)/i.test(req.headers['content-type']??'')){req.resume();return error(400,'content_type');}
  if(Number(req.headers['content-length'])>MAX_BYTES){req.resume();return error(413,'body_too_large');}
  try{
   let bytes=0;const chunks=[];
   for await(const chunk of req){bytes+=chunk.length;if(bytes>MAX_BYTES){error(413,'body_too_large');return;}chunks.push(chunk);}
   let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return error(400,'invalid_json');}
   reply(200,applySync(userStore,body));
  }catch(e){if(req.aborted||res.destroyed)return;if(e instanceof ValidationError)return error(['protocol_mismatch','workspace_mismatch'].includes(e.code)?409:400,e.code);error(500,'internal_error');}
 });
}
