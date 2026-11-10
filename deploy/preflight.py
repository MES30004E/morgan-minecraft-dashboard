"""Read-only Crafty check and scoped agent identity check. Never claims a command."""
import asyncio
import os
from pathlib import Path
import shlex
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'agent'))
from crafty import Crafty
from archive_store import private_read,LocalArchiveStore
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
    print('Checking local Crafty TLS and read-only statistics…')
    crafty=Crafty(values['CRAFTY_URL'],values['CRAFTY_SERVER_ID'],values['CRAFTY_TOKEN'],values['CRAFTY_CA_FILE'])
    await asyncio.to_thread(crafty.snapshot)
    print('Crafty certificate and read-only API check passed.')
    client=await acreate_client(values['SUPABASE_URL'],values['SUPABASE_PUBLISHABLE_KEY'],AsyncClientOptions(auto_refresh_token=False,persist_session=False,postgrest_client_retry=False))
    try:
        await client.auth.sign_in_with_password(dict(email=values['AGENT_EMAIL'],password=values['AGENT_PASSWORD']))
        response=await client.rpc('agent_identity',{}).execute()
        if response.data!='c18848e0-5448-433a-909d-804ad3680713':raise ValueError('Agent is not registered for this server')
        print('Dedicated agent identity is correctly scoped.')
    finally:
        await client.auth.close();await client.postgrest.aclose()
    if values.get('ENABLE_ARCHIVES','false').lower()=='true':
        store=LocalArchiveStore(Path(values['ARCHIVE_DIRECTORY']),private_read(Path(values['ARCHIVE_KEY_FILE'])),int(values.get('ARCHIVE_MAX_BYTES','1073741824')))
        health=store.health()
        if not health['writable']:raise ValueError('Archive quota or free-space reserve prevents writes')
        print('Private archive key, directory and storage reserve check passed.')
    print('Preflight passed. No Minecraft commands were sent; no world or backup files were changed.')

if __name__=='__main__':
    try:asyncio.run(check(config(sys.argv[1] if len(sys.argv)>1 else '/etc/morgan-minecraft-agent/agent.env')))
    except Exception as error:
        print('Preflight failed: '+type(error).__name__+'. Check the corresponding installation step; credentials are not printed.',file=sys.stderr)
        sys.exit(1)
