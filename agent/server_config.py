"""Local administrator-owned mappings; cloud metadata never chooses a local target."""
from pathlib import Path
import os,stat,re
from types import SimpleNamespace
from uuid import UUID
from urllib.parse import urlsplit


def load_servers(document):
    if not isinstance(document,dict) or set(document)!={'servers'} or not isinstance(document['servers'],list) or not 1<=len(document['servers'])<=10:
        raise ValueError('Configure one to ten server mappings')
    result=[];ids=set();controllers=set();sockets=set();keys=set();groups=set()
    allowed={'server_id','crafty_server_id','crafty_url','crafty_token','crafty_ca_file','backup_directory','upload_console','link_socket','link_key_file','archive_key_file','link_group'}
    for entry in document['servers']:
        if not isinstance(entry,dict) or set(entry)-allowed:raise ValueError('Unknown local server configuration')
        item=dict(entry)
        for field in ('server_id','crafty_server_id'):
            if str(UUID(item[field]))!=item[field]:raise ValueError('Canonical UUID required')
        controller=(canonical_controller(item.get('crafty_url',os.environ.get('CRAFTY_URL','https://localhost:8443'))),item['crafty_server_id'])
        if item['server_id'] in ids or controller in controllers:raise ValueError('Duplicate server or Crafty target')
        ids.add(item['server_id']);controllers.add(controller)
        for field in ('crafty_ca_file','backup_directory','link_socket','link_key_file','archive_key_file'):
            if item.get(field) and (not Path(item[field]).is_absolute() or '..' in Path(item[field]).parts):raise ValueError('Local paths must be absolute')
        if bool(item.get('link_socket'))!=bool(item.get('link_key_file')):raise ValueError('Bridge needs a socket and private key')
        if item.get('link_socket'):
            if item['link_socket'] in sockets or item['link_key_file'] in keys or item.get('link_group','morgan-minecraft-link') in groups:raise ValueError('Each bridge needs its own socket and key')
            sockets.add(item['link_socket']);keys.add(item['link_key_file']);groups.add(item.get('link_group','morgan-minecraft-link'))
            if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}',item.get('link_group','morgan-minecraft-link')):raise ValueError('Invalid local bridge group')
        if 'upload_console' in item and type(item['upload_console']) is not bool:raise ValueError('Console flag must be boolean')
        result.append(item)
    return result


class ScopedCloud:
    """Inject a locally pinned server ID into every allowlisted agent RPC."""
    def __init__(self,cloud,server_id):self.cloud,self.server_id=cloud,str(UUID(server_id))
    def rpc(self,name,args=None):
        request=self.cloud.rpc('agent_call',dict(target=self.server_id,operation=name,payload=args or {}))
        async def execute():
            response=await request.execute()
            if name in ('claim_command','recover_commands'):
                if not isinstance(response.data,list) or any(row.get('server_id')!=self.server_id for row in response.data):
                    raise ValueError('Cloud command belongs to a different server')
            if name=='identity' and response.data!=self.server_id:raise ValueError('Agent binding mismatch')
            return response
        return SimpleNamespace(execute=execute)


def read_config(path):
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
    with os.fdopen(fd,'rb') as stream:
        info=os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid not in (0,os.getuid()) or info.st_mode & 0o027:
            raise ValueError('Configuration must be private and administrator or service owned')
        if info.st_mode & 0o040 and os.getuid()!=0 and info.st_gid!=os.getgid():raise ValueError('Configuration group is not the service group')
        value=stream.read(65537)
        if len(value)>65536:raise ValueError('Configuration too large')
        return value


def require_partitioned_state(state,archives):
    if (Path(state)/'executions.db').exists() or any(Path(archives).glob('*.enc')) or any(Path(archives).glob('*.manifest.json')):
        raise ValueError('Legacy state requires an approved offline migration; never ignore an execution journal')


def canonical_controller(url):
    parsed=urlsplit(url)
    if parsed.scheme!='https' or parsed.hostname not in ('localhost','127.0.0.1','::1') or parsed.username or parsed.password or parsed.path not in ('','/') or parsed.query or parsed.fragment:
        raise ValueError('Crafty must use local HTTPS')
    port=parsed.port if parsed.port is not None else 443
    if not 1<=port<=65535:raise ValueError('Invalid Crafty port')
    # Conservative: loopback aliases on the same port represent one controller.
    return ('loopback',port)
