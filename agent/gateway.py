"""Authenticated Fabric bridge on a protected local Unix socket, never TCP."""
import asyncio
import base64
import hashlib
import hmac
import json
import re
import sqlite3
import time
from uuid import UUID


def encode_message(value,key):
    payload=json.dumps(value,separators=(',',':')).encode()
    return json.dumps(dict(payload=base64.b64encode(payload).decode(),mac=hmac.new(key,payload,hashlib.sha256).hexdigest()),separators=(',',':')).encode()+b'\n'


def decode_message(raw,key,*,now=None):
    try:
        if len(raw)>8192:raise ValueError()
        envelope=json.loads(raw)
        if set(envelope)!={'payload','mac'}:raise ValueError()
        payload=base64.b64decode(envelope['payload'],validate=True)
        expected=hmac.new(key,payload,hashlib.sha256).hexdigest()
        if not hmac.compare_digest(envelope['mac'],expected):raise ValueError()
        value=json.loads(payload)
        required={'nonce','issued_at','operation','player_uuid','player_name','online_mode'}
        if not required<=set(value) or set(value)-required-{'code','confirmed','statistics'}:raise ValueError()
        if str(UUID(value['nonce']))!=value['nonce'] or str(UUID(value['player_uuid']))!=value['player_uuid']:raise ValueError()
        if value['online_mode'] is not True or not re.fullmatch(r'[A-Za-z0-9_]{3,16}',value['player_name']):raise ValueError()
        if value['operation'] not in ('begin','verify','profile','unlink','stats'):raise ValueError()
        if value['operation']=='stats':
            stats=value.get('statistics')
            fields={'play_time_ticks','deaths','mob_kills','blocks_mined','advancements_done','advancements_total'}
            if not isinstance(stats,dict) or set(stats)!=fields|{'online'} or type(stats['online']) is not bool:raise ValueError()
            if any(type(stats[k]) is not int or not 0<=stats[k]<=2**53 for k in fields):raise ValueError()
        if type(value['issued_at']) is not int or abs((time.time() if now is None else now)-value['issued_at'])>60:raise ValueError()
        if 'code' in value and not re.fullmatch(r'[a-f0-9]{32}',value['code']):raise ValueError()
        if 'confirmed' in value and type(value['confirmed']) is not bool:raise ValueError()
        return value
    except (ValueError,TypeError,KeyError,AttributeError):
        raise ValueError('Invalid bridge message') from None


class LocalBridge:
    def __init__(self,cloud,path,key):
        if len(key)!=32:raise ValueError('Bridge requires a 256-bit key')
        self.cloud,self.key=cloud,key
        self.db=sqlite3.connect(str(path),timeout=10)
        self.db.execute('CREATE TABLE IF NOT EXISTS bridge_requests (nonce TEXT PRIMARY KEY, created REAL NOT NULL)')
        self.db.commit()
        self.slots=asyncio.Semaphore(8)

    async def process(self,value):
        with self.db:
            self.db.execute('DELETE FROM bridge_requests WHERE created < ?',(time.time()-3600,))
            if self.db.execute('SELECT count(*) FROM bridge_requests WHERE created > ?',(time.time()-60,)).fetchone()[0]>=120:
                raise ValueError('Bridge busy')
            if self.db.execute('INSERT OR IGNORE INTO bridge_requests VALUES (?,?)',(value['nonce'],time.time())).rowcount!=1:
                raise ValueError('Bridge replay rejected')
        op=value['operation'];args=dict(player_uuid=value['player_uuid'])
        if op=='begin':
            name='begin_game_link';args['player_name']=value['player_name']
        elif op=='verify':
            name='verify_link';args.update(code=value.get('code',''),player_name=value['player_name'],confirmed=value.get('confirmed',False))
        elif op=='profile':name='game_profile'
        elif op=='stats':name='record_player_stats';args.update(player_name=value['player_name'],stats=value['statistics'])
        else:
            if value.get('confirmed') is not True:return 'Run /unlink confirm to remove your website link. Inventory is not changed.'
            name='unlink_game_identity'
        result=await self.cloud.rpc(name,args).execute()
        if op=='begin':return 'Open https://mes30004e.github.io/morgan-minecraft-dashboard/ and sign in. Enter pairing code '+str(result.data)+'. Then use /verify '+str(result.data)+' to review and confirm the website account. Code expires in 5 minutes.'
        return str(result.data)

    async def handle(self,reader,writer):
        nonce='unknown'
        try:
            async with self.slots:
                raw=await asyncio.wait_for(reader.readline(),timeout=5)
                value=decode_message(raw,self.key);nonce=value['nonce']
                message=await asyncio.wait_for(self.process(value),timeout=15)
                writer.write(encode_message(dict(nonce=nonce,message=message),self.key))
                await writer.drain()
        except Exception:
            try:
                writer.write(encode_message(dict(nonce=nonce,message='Link service unavailable or request rejected. No website access was granted.'),self.key));await writer.drain()
            except Exception:pass
        finally:
            writer.close()
            await writer.wait_closed()

    def close(self):self.db.close()
