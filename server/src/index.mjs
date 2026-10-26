import {randomBytes,createHash} from 'node:crypto';import {mkdirSync,readdirSync,readFileSync} from 'node:fs';import {resolve,join} from 'node:path';import {parseArgs} from 'node:util';
import {openStore} from './store.mjs';import {createHttpServer} from './http.mjs';
const {values}=parseArgs({options:{data:{type:'string',default:'./day-data'},port:{type:'string',default:'18766'},'generate-token':{type:'boolean',default:false}}});
if(values['generate-token']){process.stdout.write(randomBytes(32).toString('base64url')+'\n');}else{
 const token=process.env.DAY_SYNC_TOKEN??'';
 if(!/^[A-Za-z0-9_-]{43,}$/.test(token)||Buffer.from(token,'base64url').length<32){console.error('DAY_SYNC_TOKEN: требуется ключ минимум 32 байта base64url');process.exitCode=1;}else{
  const port=Number(values.port);if(!Number.isInteger(port)||port<0||port>65535)throw Error('invalid port');
  const directory=resolve(values.data);mkdirSync(directory,{recursive:true});
  // The owner keeps sync.sqlite; every other person lives in users/<name>/ with key.sha256 and an own sync.sqlite.
  const stores=new Map([[createHash('sha256').update(token).digest('hex'),openStore(join(directory,'sync.sqlite'))]]);
  const users=join(directory,'users');mkdirSync(users,{recursive:true});
  for(const name of readdirSync(users)){
   let hash;try{hash=readFileSync(join(users,name,'key.sha256'),'utf8').trim();}catch{continue;}
   if(/^[0-9a-f]{64}$/.test(hash)&&!stores.has(hash))stores.set(hash,openStore(join(users,name,'sync.sqlite')));
  }
  const closeAll=()=>{for(const store of stores.values())store.close();};
  const server=createHttpServer({stores});
  server.on('error',()=>{console.error('Не удалось запустить локальный сервер');closeAll();process.exitCode=1;});
  server.listen(port,'127.0.0.1',()=>console.log(`День Sync: http://127.0.0.1:${server.address().port}, людей: ${stores.size}`));
  for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>server.close(closeAll));
 }
}
