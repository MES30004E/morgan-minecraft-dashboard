"""Narrow localhost-only Crafty API v2 adapter. Never executes a shell."""
import json
import re
import ssl
import time
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPSHandler, HTTPRedirectHandler
from uuid import UUID
from control import validate


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Crafty redirects are forbidden')


def parse_memory(value):
    match = re.fullmatch(r'(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)',str(value))
    if not match:
        return None
    number, unit = match.groups()
    factor = {'B':1,'KB':1000,'MB':10**6,'GB':10**9,'TB':10**12,
              'KiB':1024,'MiB':1024**2,'GiB':1024**3,'TiB':1024**4}[unit]
    return int(float(number)*factor)


def redact_log(line):
    if re.search(r'(?i)(/(?:link|verify|register)\b|authorization|bearer\s|password|secret|token|sb_secret_|GOCSPX-)',line):
        return '[sensitive log line omitted]'
    return re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',line)[:300]


class Crafty:
    def __init__(self, base_url, server_id, token, ca_file):
        parsed=urlsplit(base_url)
        if parsed.scheme!='https' or parsed.hostname not in ('localhost','127.0.0.1','::1') or parsed.username or parsed.password or parsed.path not in ('','/') or parsed.query or parsed.fragment:
            raise ValueError('Crafty must use a localhost HTTPS URL')
        self.server_id=str(UUID(server_id))
        self.base_url=base_url.rstrip('/')
        self.token=token
        context=ssl.create_default_context(cafile=ca_file)
        context.minimum_version=ssl.TLSVersion.TLSv1_2
        self.opener=build_opener(NoRedirect(),HTTPSHandler(context=context))

    def request(self,method,path,body=None):
        req=Request(self.base_url+path,data=body,method=method,headers={
            'Authorization':'Bearer '+self.token,'Content-Type':'text/plain' if body is not None else 'application/json'})
        with self.opener.open(req,timeout=15) as response:
            raw=response.read(1024*1024+1)
            if len(raw)>1024*1024:
                raise ValueError('Crafty response too large')
            result=json.loads(raw)
            if result.get('status')!='ok':
                raise ValueError('Crafty did not confirm request acceptance')
            return result.get('data',{})

    def execute(self,command,*,now=None):
        command=validate(command,now=time.time() if now is None else now)
        action=command['operation']
        base='/api/v2/servers/'+self.server_id
        if action in ('start','stop','restart'):
            self.request('POST',base+'/action/'+action+'_server')
        else:
            verb={'kick':'kick','ban':'ban','pardon':'pardon','whitelist_add':'whitelist add','whitelist_remove':'whitelist remove'}[action]
            self.request('POST',base+'/stdin',(verb+' '+command['arguments']['player']).encode('ascii'))

    def snapshot(self):
        data=self.request('GET','/api/v2/servers/'+self.server_id+'/stats')
        running=data.get('running')
        state='online' if running is True else 'offline' if running is False else 'unknown'
        cpu=data.get('cpu')
        try:cpu=float(cpu)
        except (ValueError,TypeError):cpu=None
        if cpu is not None and not 0<=cpu<=100:cpu=None
        players=data.get('players',[])
        if isinstance(players,str):
            try:players=json.loads(players)
            except ValueError:players=[]
        names=[{'name':p} for p in players if isinstance(p,str) and re.fullmatch(r'[A-Za-z0-9_]{3,16}',p)] if isinstance(players,list) else []
        # Crafty's timestamp timezone is unspecified: do not invent uptime.
        return dict(server_state=state,cpu=cpu,memory=parse_memory(data.get('mem')),uptime=None,online_players=names[:100])

    def console(self):
        lines=self.request('GET','/api/v2/servers/'+self.server_id+'/logs?colors=false&raw=false&html=false')
        if not isinstance(lines,list):raise ValueError('Unexpected log response')
        return [redact_log(str(line)) for line in lines[-100:]]
