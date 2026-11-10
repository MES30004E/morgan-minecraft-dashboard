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
from datetime import datetime,timezone
from pathlib import Path
from supabase import acreate_client, AsyncClientOptions
from control import Journal
from crafty import Crafty
from worker import Worker
from gateway import LocalBridge
from backups import scan_backups
from archive_store import LocalArchiveStore, private_read
from archive_worker import DailyArchiver
from server_config import load_servers,ScopedCloud,read_config,require_partitioned_state


def log(event,**fields):
    # Never log payloads, exception messages, credentials, player challenges or URLs.
    print(json.dumps(dict(event=event,**fields)),flush=True)


async def archive_loop(cloud,stop,store,status):
    archiver=DailyArchiver(store)
    while not stop.is_set():
        delay=86400
        try:
            status['archive_state']='running'
            store.prune()
            counts=await archiver.run_once(cloud)
            status.update(archive_state='ok',last_archive_success=datetime.now(timezone.utc).isoformat())
            log('archives_verified',batches=counts,**store.health())
        except Exception as error:
            # Failure never acknowledges the failed batch or permits deletion.
            delay=3600
            status['archive_state']='failed'
            log('archive_failed',error_type=type(error).__name__)
        try:await asyncio.wait_for(stop.wait(),timeout=delay)
        except asyncio.TimeoutError:pass


async def server_loop(raw_cloud,config,stop,wake,state_root,archive_root,archive_quota):
    server_id=config['server_id'];cloud=ScopedCloud(raw_cloud,server_id)
    state=state_root/server_id;state.mkdir(mode=0o700,parents=True,exist_ok=True)
    journal=Journal(state/'executions.db')
    crafty=Crafty(config.get('crafty_url',os.environ.get('CRAFTY_URL','https://localhost:8443')),config['crafty_server_id'],config.get('crafty_token',os.environ['CRAFTY_TOKEN']),config.get('crafty_ca_file',os.environ['CRAFTY_CA_FILE']))
    archive_store=None;archive_task=None;local_server=None;bridge=None
    archive_status=dict(archive_state='disabled',archive_bytes=None,quota_bytes=None,disk_free_bytes=None,last_archive_success=None)
    if os.environ.get('ENABLE_ARCHIVES','false').lower()=='true':
        try:
            archive_store=LocalArchiveStore(archive_root/server_id,private_read(Path(config.get('archive_key_file',os.environ['ARCHIVE_KEY_FILE']))),max_bytes=archive_quota)
        except Exception as error:
            archive_status['archive_state']='failed';log('archive_configuration_failed',server_id=server_id,error_type=type(error).__name__)
    try:
        await cloud.rpc('identity',{}).execute()
        worker=Worker(cloud,journal,crafty.execute)
        if config.get('link_socket'):
            socket_path=Path(config['link_socket']);key=bytes.fromhex(private_read(Path(config['link_key_file'])).decode().strip())
            if socket_path.exists():
                info=socket_path.lstat()
                if not stat.S_ISSOCK(info.st_mode) or info.st_uid!=os.getuid():raise ValueError('Refusing unexpected bridge path')
                socket_path.unlink()
            bridge=LocalBridge(cloud,state/'executions.db',key)
            local_server=await asyncio.start_unix_server(bridge.handle,path=str(socket_path),limit=8192,backlog=16)
            os.chown(socket_path,-1,grp.getgrnam(config.get('link_group','morgan-minecraft-link')).gr_gid);socket_path.chmod(0o660)
        pending=await cloud.rpc('recover_commands',{}).execute()
        for row in pending.data:
            outcome='completed' if journal.state(row['id'])=='completed' else 'uncertain'
            await cloud.rpc('finish_command',dict(command_id=row['id'],token=row['claim_token'],outcome=outcome,summary='Recovered from durable execution journal' if outcome=='completed' else 'Restart interrupted dispatch; owner reconciliation required')).execute()
        if archive_store:archive_task=asyncio.create_task(archive_loop(cloud,stop,archive_store,archive_status))
        last_console=0;last_backups=0;delay=2
        while not stop.is_set():
            wake.clear()
            try:
                processed=await worker.process_one()
                if archive_store:
                    health=archive_store.health();archive_status.update(archive_bytes=health['used_bytes'],quota_bytes=health['max_bytes'],disk_free_bytes=health['disk_free_bytes'])
                if time.monotonic()-last_console>=120:
                    await cloud.rpc('publish_agent_health',archive_status).execute()
                    if config.get('upload_console',False):
                        try:await cloud.rpc('publish_console',dict(log_lines=await asyncio.to_thread(crafty.console))).execute()
                        except Exception:log('console_unavailable',server_id=server_id)
                    last_console=time.monotonic()
                if config.get('backup_directory') and time.monotonic()-last_backups>=21600:
                    try:await cloud.rpc('publish_backups',dict(archives=await asyncio.to_thread(scan_backups,Path(config['backup_directory'])))).execute()
                    except Exception:log('backup_metadata_unavailable',server_id=server_id)
                    last_backups=time.monotonic()
                delay=2
                if processed:wake.set()
                timeout=120
            except Exception as error:
                log('server_disconnected',server_id=server_id,error_type=type(error).__name__,retry_seconds=delay)
                timeout=delay+random.random();delay=min(delay*2,300)
            try:await asyncio.wait_for(wake.wait(),timeout=timeout)
            except asyncio.TimeoutError:pass
    finally:
        if archive_task:archive_task.cancel();await asyncio.gather(archive_task,return_exceptions=True)
        if local_server:local_server.close();await local_server.wait_closed()
        if bridge:bridge.close()
        journal.close()


async def resilient_server(cloud,config,stop,wake,*roots):
    delay=2
    while not stop.is_set():
        try:await server_loop(cloud,config,stop,wake,*roots)
        except Exception as error:log('server_setup_failed',server_id=config['server_id'],error_type=type(error).__name__)
        if stop.is_set():break
        try:await asyncio.wait_for(stop.wait(),timeout=delay+random.random())
        except asyncio.TimeoutError:pass
        delay=min(delay*2,300)


async def collect_metrics(configs):
    async def sample(config):
        try:
            crafty=Crafty(config.get('crafty_url',os.environ.get('CRAFTY_URL','https://localhost:8443')),config['crafty_server_id'],config.get('crafty_token',os.environ['CRAFTY_TOKEN']),config.get('crafty_ca_file',os.environ['CRAFTY_CA_FILE']))
            value=await asyncio.to_thread(crafty.snapshot)
        except Exception:value=dict(server_state='unknown',cpu=None,memory=None,uptime=None,online_players=[])
        return dict(server_id=config['server_id'],snapshot=value)
    return await asyncio.gather(*(sample(config) for config in configs))


async def metrics_loop(cloud,configs,stop):
    delay=60
    while not stop.is_set():
        try:
            samples=await collect_metrics(configs)
            result=await cloud.rpc('agent_metrics',dict(samples=samples)).execute()
            rejected=sum(not row.get('accepted',False) for row in result.data)
            if rejected:log('metrics_rejected',server_count=rejected)
            delay=60
        except Exception as error:
            log('metrics_unavailable',error_type=type(error).__name__);delay=min(delay*2,300)
        try:await asyncio.wait_for(stop.wait(),timeout=delay)
        except asyncio.TimeoutError:pass


async def serve():
    state=Path(os.environ.get('STATE_DIRECTORY','/var/lib/morgan-minecraft-agent').split(':')[0]);state.mkdir(parents=True,exist_ok=True)
    lock=open(state/'agent.lock','a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    # Root-managed local configuration, never a browser/database filesystem path.
    path=Path(os.environ.get('SERVERS_CONFIG','/etc/morgan-minecraft-agent/servers.json'))
    configs=load_servers(json.loads(read_config(path)))
    require_partitioned_state(state,Path(os.environ.get('ARCHIVE_DIRECTORY','/var/lib/morgan-minecraft/archives')))
    stop=asyncio.Event();wakes={c['server_id']:asyncio.Event() for c in configs}
    loop=asyncio.get_running_loop()
    for sig in (signal.SIGTERM,signal.SIGINT):loop.add_signal_handler(sig,stop.set)
    delay=2
    try:
        while not stop.is_set():
            cloud=None;tasks=[]
            try:
                cloud=await acreate_client(os.environ['SUPABASE_URL'],os.environ['SUPABASE_PUBLISHABLE_KEY'],AsyncClientOptions(auto_refresh_token=False,persist_session=False,postgrest_client_timeout=20,postgrest_client_retry=False))
                await cloud.auth.sign_in_with_password(dict(email=os.environ['AGENT_EMAIL'],password=os.environ['AGENT_PASSWORD']))
                def wake_all(payload=None):
                    for wake in wakes.values():wake.set()
                await cloud.channel('agent-commands').on_postgres_changes('INSERT',schema='public',table='commands',callback=wake_all).subscribe(lambda status,error:wake_all())
                quota=int(os.environ.get('ARCHIVE_MAX_BYTES','1073741824'))//len(configs)
                archive_root=Path(os.environ.get('ARCHIVE_DIRECTORY','/var/lib/morgan-minecraft/archives'))
                tasks=[asyncio.create_task(resilient_server(cloud,c,stop,wakes[c['server_id']],state,archive_root,quota)) for c in configs]
                tasks.append(asyncio.create_task(metrics_loop(cloud,configs,stop)))
                delay=2;log('connected',server_count=len(configs))
                while not stop.is_set():
                    try:await asyncio.wait_for(stop.wait(),timeout=1800)
                    except asyncio.TimeoutError:await cloud.auth.refresh_session()
            except Exception as error:
                log('disconnected',error_type=type(error).__name__,retry_seconds=delay)
                try:await asyncio.wait_for(stop.wait(),timeout=delay+random.random())
                except asyncio.TimeoutError:pass
                delay=min(delay*2,300)
            finally:
                for task in tasks:task.cancel()
                await asyncio.gather(*tasks,return_exceptions=True)
                if cloud:
                    try:await cloud.remove_all_channels()
                    except Exception:pass
                    try:await cloud.auth.close();await cloud.postgrest.aclose()
                    except Exception:pass
    finally:lock.close();log('stopped')


if __name__=='__main__':
    os.umask(0o077)
    asyncio.run(serve())
