import {randomBytes,createHash} from 'node:crypto';import {mkdirSync} from 'node:fs';import {resolve,join} from 'node:path';import {parseArgs} from 'node:util';
import {openStore} from './store.mjs';import {createHttpServer} from './http.mjs';
const {values}=parseArgs({options:{data:{type:'string',default:'./day-data'},port:{type:'string',default:'18766'},'generate-token':{type:'boolean',default:false}}});
if(values['generate-token']){process.stdout.write(randomBytes(32).toString('base64url')+'\n');}else{
 const token=process.env.DAY_SYNC_TOKEN??'';
 if(!/^[A-Za-z0-9_-]{43,}$/.test(token)||Buffer.from(token,'base64url').length<32){console.error('DAY_SYNC_TOKEN: требуется ключ минимум 32 байта base64url');process.exitCode=1;}else{
  const port=Number(values.port);if(!Number.isInteger(port)||port<0||port>65535)throw Error('invalid port');
  const directory=resolve(values.data);mkdirSync(directory,{recursive:true});const store=openStore(join(directory,'sync.sqlite'));
  const server=createHttpServer({store,tokenHash:createHash('sha256').update(token).digest()});
  server.on('error',()=>{console.error('Не удалось запустить локальный сервер');store.close();process.exitCode=1;});
  server.listen(port,'127.0.0.1',()=>console.log(`День Sync: http://127.0.0.1:${server.address().port}`));
  for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>server.close(()=>store.close()));
 }
}
