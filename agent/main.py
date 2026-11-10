"""Outbound-only systemd entry point. No inbound sockets or shell execution."""
import asyncio
import fcntl
import grp
import json
import os
import random
import signal
import stat
import time
from pathlib import Path
from supabase import acreate_client, AsyncClientOptions
from control import Journal
from crafty import Crafty
from worker import Worker
from gateway import LocalBridge
from backups import scan_backups
from archive_store import LocalArchiveStore, private_read
from archive_worker import DailyArchiver


def log(event,**fields):
    # Never log payloads, exception messages, credentials, player challenges or URLs.
    print(json.dumps(dict(event=event,**fields)),flush=True)


async def archive_loop(cloud,stop,store):
    archiver=DailyArchiver(store)
    while not stop.is_set():
        delay=86400
        try:
            store.prune()
            counts=await archiver.run_once(cloud)
            log('archives_verified',batches=counts,**store.health())
        except Exception as error:
            # Failure never acknowledges the failed batch or permits deletion.
            delay=3600
            log('archive_failed',error_type=type(error).__name__)
        try:await asyncio.wait_for(stop.wait(),timeout=delay)
        except asyncio.TimeoutError:pass


async def serve():
    state=Path(os.environ.get('STATE_DIRECTORY','/var/lib/morgan-minecraft-agent').split(':')[0])
    state.mkdir(parents=True,exist_ok=True)
    lock=open(state/'agent.lock','a')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    journal=Journal(state/'executions.db')
    archive_store=None
    if os.environ.get('ENABLE_ARCHIVES','false').lower()=='true':
        try:
            archive_store=LocalArchiveStore(Path(os.environ.get('ARCHIVE_DIRECTORY','/var/lib/morgan-minecraft/archives')),
                private_read(Path(os.environ.get('ARCHIVE_KEY_FILE','/etc/morgan-minecraft-agent/archive.key'))),
                max_bytes=int(os.environ.get('ARCHIVE_MAX_BYTES','1073741824')))
        except Exception as error:log('archive_configuration_failed',error_type=type(error).__name__)
    crafty=Crafty(os.environ['CRAFTY_URL'],os.environ['CRAFTY_SERVER_ID'],os.environ['CRAFTY_TOKEN'],os.environ['CRAFTY_CA_FILE'])
    stop=asyncio.Event();wake=asyncio.Event()
    loop=asyncio.get_running_loop()
    for sig in (signal.SIGTERM,signal.SIGINT):loop.add_signal_handler(sig,lambda:(stop.set(),wake.set()))
    delay=2
    try:
        while not stop.is_set():
            cloud=None;local_server=None;bridge=None;archive_task=None
            try:
                cloud=await acreate_client(os.environ['SUPABASE_URL'],os.environ['SUPABASE_PUBLISHABLE_KEY'],AsyncClientOptions(auto_refresh_token=False,persist_session=False,postgrest_client_timeout=20,postgrest_client_retry=False))
                login=await cloud.auth.sign_in_with_password(dict(email=os.environ['AGENT_EMAIL'],password=os.environ['AGENT_PASSWORD']))
                if not login.user:raise RuntimeError('Agent authentication failed')
                worker=Worker(cloud,journal,crafty.execute)
                if os.environ.get('ENABLE_LINK_BRIDGE','false').lower()=='true':
                    socket_path=Path(os.environ.get('LINK_SOCKET','/var/lib/morgan-minecraft-link/bridge.sock'))
                    key=bytes.fromhex(Path(os.environ.get('LINK_KEY_FILE','/etc/morgan-minecraft-agent/bridge.key')).read_text().strip())
                    if socket_path.exists():
                        info=socket_path.lstat()
                        if not stat.S_ISSOCK(info.st_mode) or info.st_uid!=os.getuid():raise ValueError('Refusing to replace unexpected bridge path')
                        socket_path.unlink()
                    bridge=LocalBridge(cloud,state/'executions.db',key)
                    local_server=await asyncio.start_unix_server(bridge.handle,path=str(socket_path),limit=8192,backlog=16)
                    os.chown(socket_path,-1,grp.getgrnam('morgan-minecraft-link').gr_gid)
                    socket_path.chmod(0o660)
                # A lost acknowledgement is recoverable only from the durable journal.
                pending=await cloud.table('commands').select('id,claim_token').eq('claimed_by',login.user.id).in_('state',['claimed','uncertain']).execute()
                for row in pending.data:
                    outcome='completed' if journal.state(row['id'])=='completed' else 'uncertain'
                    await cloud.rpc('finish_command',dict(command_id=row['id'],token=row['claim_token'],outcome=outcome,summary='Recovered from durable execution journal' if outcome=='completed' else 'Restart interrupted dispatch; owner reconciliation required')).execute()
                channel=cloud.channel('agent-commands')
                await channel.on_postgres_changes('INSERT',schema='public',table='commands',callback=lambda payload:wake.set()).subscribe(lambda status,error:wake.set())
                wake.set();last_metrics=0;last_backups=0;last_auth=time.monotonic();delay=2
                log('connected')
                if archive_store:archive_task=asyncio.create_task(archive_loop(cloud,stop,archive_store))
                while not stop.is_set():
                    wake.clear()
                    if time.monotonic()-last_auth>=1800:
                        await cloud.auth.refresh_session();last_auth=time.monotonic()
                    processed=await worker.process_one()
                    if time.monotonic()-last_metrics>=60:
                        try:snapshot=await asyncio.to_thread(crafty.snapshot)
                        except Exception:
                            snapshot=dict(server_state='unknown',cpu=None,memory=None,uptime=None,online_players=[])
                            log('crafty_unavailable')
                        await cloud.rpc('publish_snapshot',snapshot).execute()
                        if os.environ.get('UPLOAD_CONSOLE','false').lower()=='true':
                            try:
                                lines=await asyncio.to_thread(crafty.console)
                                await cloud.rpc('publish_console',dict(log_lines=lines)).execute()
                            except Exception:log('console_unavailable')
                        last_metrics=time.monotonic()
                    if os.environ.get('BACKUP_DIRECTORY') and time.monotonic()-last_backups>=21600:
                        try:
                            archives=await asyncio.to_thread(scan_backups,Path(os.environ['BACKUP_DIRECTORY']))
                            await cloud.rpc('publish_backups',dict(archives=archives)).execute()
                        except Exception:log('backup_metadata_unavailable')
                        last_backups=time.monotonic()
                    if processed:wake.set()
                    try:await asyncio.wait_for(wake.wait(),timeout=60)
                    except asyncio.TimeoutError:pass
            except Exception as error:
                log('disconnected',error_type=type(error).__name__,retry_seconds=delay)
                try:await asyncio.wait_for(stop.wait(),timeout=delay+random.random())
                except asyncio.TimeoutError:pass
                delay=min(delay*2,300)
            finally:
                if archive_task:
                    archive_task.cancel();await asyncio.gather(archive_task,return_exceptions=True)
                if local_server:
                    local_server.close();await local_server.wait_closed()
                if bridge:bridge.close()
                if cloud:
                    try:await cloud.remove_all_channels()
                    except Exception:pass
                    try:await cloud.auth.close()
                    except Exception:pass
                    try:await cloud.postgrest.aclose()
                    except Exception:pass
    finally:
        journal.close();lock.close();log('stopped')


if __name__=='__main__':
    os.umask(0o077)
    asyncio.run(serve())
