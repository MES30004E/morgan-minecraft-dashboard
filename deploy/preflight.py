"""Read-only Crafty check and scoped agent identity check. Never claims a command."""
import asyncio
import os
import json,pwd
from pathlib import Path
import shlex
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'agent'))
from crafty import Crafty
from archive_store import private_read,LocalArchiveStore
from server_config import load_servers,read_config,ScopedCloud,require_partitioned_state
from supabase import acreate_client,AsyncClientOptions

def config(path):
    result={}
    for line in Path(path).read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):continue
        key,sep,value=line.partition('=')
        if not sep or not key.replace('_','').isalnum():raise ValueError('Invalid environment syntax')
        parts=shlex.split(value,comments=False,posix=True)
        result[key]=parts[0] if len(parts)==1 else '' if not parts else ' '.join(parts)
    if any('REPLACE' in value for value in result.values()):raise ValueError('Private configuration is incomplete')
    return result

async def check(values):
    configs=load_servers(json.loads(read_config(values.get('SERVERS_CONFIG','/etc/morgan-minecraft-agent/servers.json'))))
    require_partitioned_state(Path('/var/lib/morgan-minecraft-agent'),Path(values['ARCHIVE_DIRECTORY']))
    client=await acreate_client(values['SUPABASE_URL'],values['SUPABASE_PUBLISHABLE_KEY'],AsyncClientOptions(auto_refresh_token=False,persist_session=False,postgrest_client_retry=False))
    try:
        await client.auth.sign_in_with_password(dict(email=values['AGENT_EMAIL'],password=values['AGENT_PASSWORD']))
        for mapping in configs:
            print('Checking server '+mapping['server_id']+'…')
            crafty=Crafty(mapping.get('crafty_url',values['CRAFTY_URL']),mapping['crafty_server_id'],mapping.get('crafty_token',values['CRAFTY_TOKEN']),mapping.get('crafty_ca_file',values['CRAFTY_CA_FILE']))
            await asyncio.to_thread(crafty.snapshot)
            await ScopedCloud(client,mapping['server_id']).rpc('identity',{}).execute()
            if values.get('ENABLE_ARCHIVES','false').lower()=='true':
                store=LocalArchiveStore(Path(values['ARCHIVE_DIRECTORY'])/mapping['server_id'],private_read(Path(mapping.get('archive_key_file',values['ARCHIVE_KEY_FILE']))),int(values.get('ARCHIVE_MAX_BYTES','1073741824'))//len(configs))
                if not store.health()['writable']:raise ValueError('Archive storage reserve prevents writes')
            print('Scoped identity, Crafty TLS and archive checks passed.')
    finally:
        await client.auth.close();await client.postgrest.aclose()
    print('Preflight passed. No Minecraft commands were sent; no world or backup files were changed.')

if __name__=='__main__':
    try:
        values=config(sys.argv[1] if len(sys.argv)>1 else '/etc/morgan-minecraft-agent/agent.env')
        # Read root-only secrets first, then create/check application state as its owner.
        if os.geteuid()==0:
            account=pwd.getpwnam('morgan-agent');os.initgroups(account.pw_name,account.pw_gid);os.setgid(account.pw_gid);os.setuid(account.pw_uid)
        asyncio.run(check(values))
    except Exception as error:
        print('Preflight failed: '+type(error).__name__+'. Check the corresponding installation step; credentials are not printed.',file=sys.stderr)
        sys.exit(1)
