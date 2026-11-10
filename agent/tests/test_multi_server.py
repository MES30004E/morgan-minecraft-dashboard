import tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from server_config import load_servers,ScopedCloud

A='11111111-1111-4111-8111-111111111111'
B='22222222-2222-4222-8222-222222222222'
CRAFT='33333333-3333-4333-8333-333333333333'
class ConfigurationTests(unittest.TestCase):
 def test_two_local_mappings_and_distinct_state_roots(self):
  servers=load_servers({'servers':[{'server_id':A,'crafty_server_id':CRAFT},{'server_id':B,'crafty_server_id':B}]})
  self.assertEqual([s['server_id'] for s in servers],[A,B])
 def test_duplicate_server_or_crafty_mapping_is_rejected(self):
  for servers in [[{'server_id':A,'crafty_server_id':CRAFT}]*2,[{'server_id':A,'crafty_server_id':CRAFT},{'server_id':B,'crafty_server_id':CRAFT}]]:
   with self.assertRaises(ValueError):load_servers({'servers':servers})
 def test_browser_style_paths_and_unknown_configuration_rejected(self):
  for entry in [{'server_id':A,'crafty_server_id':CRAFT,'shell':'stop'},{'server_id':'../../escape','crafty_server_id':CRAFT}]:
   with self.assertRaises(ValueError):load_servers({'servers':[entry]})
class ScopedTests(unittest.IsolatedAsyncioTestCase):
 async def test_every_rpc_is_bound_to_configured_server(self):
  calls=[]
  class Cloud:
   def rpc(self,name,args):
    calls.append((name,args))
    async def execute():return SimpleNamespace(data=[])
    return SimpleNamespace(execute=execute)
  a,b=ScopedCloud(Cloud(),A),ScopedCloud(Cloud(),B)
  await a.rpc('claim_command',{}).execute();await b.rpc('publish_snapshot',{'server_state':'offline'}).execute()
  self.assertEqual(calls[0],('agent_call',{'target':A,'operation':'claim_command','payload':{}}))
  self.assertEqual(calls[1][1]['target'],B)
 async def test_adapter_rejects_cross_server_claim_before_local_dispatch(self):
  class Cloud:
   def rpc(self,name,args):
    async def execute():return SimpleNamespace(data=[{'server_id':B}])
    return SimpleNamespace(execute=execute)
  with self.assertRaises(ValueError):await ScopedCloud(Cloud(),A).rpc('claim_command',{}).execute()

class RuntimeTests(unittest.IsolatedAsyncioTestCase):
 async def test_bad_crafty_configuration_does_not_hide_other_server_metrics(self):
  from unittest.mock import patch
  from main import collect_metrics
  class Adapter:
   def __init__(self,url,server_id,*args):
    if server_id==CRAFT:raise ValueError('invalid certificate')
   def snapshot(self):return {'server_state':'online','cpu':3,'memory':4,'uptime':None,'online_players':[]}
  with patch('main.Crafty',Adapter),patch.dict('os.environ',{'CRAFTY_TOKEN':'test','CRAFTY_CA_FILE':'test'}):
   rows=await collect_metrics([{'server_id':A,'crafty_server_id':CRAFT},{'server_id':B,'crafty_server_id':B}])
  self.assertEqual(rows[0]['snapshot']['server_state'],'unknown')
  self.assertEqual(rows[1]['snapshot']['server_state'],'online')
 async def test_same_delivery_id_is_independent_in_server_journals(self):
  from control import Journal
  from worker import Worker
  calls=[]
  class Cloud:
   def rpc(self,name,args):
    async def execute():
     if args['operation']=='claim_command':return SimpleNamespace(data=[dict(server_id=args['target'],id=CRAFT,operation='start',arguments={},expires_at='2099-01-01T00:00:00+00:00',claim_token='test')])
     return SimpleNamespace(data=None)
    return SimpleNamespace(execute=execute)
  with tempfile.TemporaryDirectory() as root:
   journals=[Journal(Path(root)/name) for name in ('a.db','b.db')]
   try:
    for server,journal in zip((A,B),journals):
     worker=Worker(ScopedCloud(Cloud(),server),journal,lambda command,s=server:calls.append(s))
     await worker.process_one();await worker.process_one()
   finally:
    for journal in journals:journal.close()
  self.assertEqual(calls,[A,B])

class ConfigFileTests(unittest.TestCase):
 def test_configuration_permissions_and_symlinks_are_enforced(self):
  from server_config import read_config
  with tempfile.TemporaryDirectory() as root:
   file=Path(root)/'servers.json';file.write_text('{}');file.chmod(0o600)
   self.assertEqual(read_config(file),b'{}')
   file.chmod(0o644)
   with self.assertRaises(ValueError):read_config(file)
   link=Path(root)/'link';link.symlink_to(file)
   with self.assertRaises((ValueError,OSError)):read_config(link)
 def test_two_bridges_cannot_share_a_unix_group(self):
  rows=[dict(server_id=s,crafty_server_id=s,link_socket='/var/lib/links/'+s+'/bridge.sock',link_key_file='/etc/keys/'+s,link_group='shared') for s in (A,B)]
  with self.assertRaises(ValueError):load_servers({'servers':rows})

class LegacyStateTests(unittest.TestCase):
 def test_legacy_journal_is_not_silently_ignored(self):
  from server_config import require_partitioned_state
  with tempfile.TemporaryDirectory() as root:
   state=Path(root)/'state';archives=Path(root)/'archives';state.mkdir();archives.mkdir()
   require_partitioned_state(state,archives)
   (state/'executions.db').write_bytes(b'existing journal')
   with self.assertRaises(ValueError):require_partitioned_state(state,archives)

class CanonicalTargetTests(unittest.TestCase):
 def test_url_aliases_and_environment_fallback_cannot_duplicate_a_controller(self):
  from unittest.mock import patch
  for left,right in [('https://localhost:8443','https://localhost:8443/'),('https://localhost:8443','https://127.0.0.1:8443'),('https://[::1]:8443','https://localhost:8443'),('https://localhost','https://127.0.0.1:443')]:
   with self.subTest(left=left,right=right),self.assertRaises(ValueError):
    load_servers({'servers':[dict(server_id=A,crafty_server_id=CRAFT,crafty_url=left),dict(server_id=B,crafty_server_id=CRAFT,crafty_url=right)]})
  with patch.dict('os.environ',{'CRAFTY_URL':'https://127.0.0.1:9000/'}),self.assertRaises(ValueError):
   load_servers({'servers':[dict(server_id=A,crafty_server_id=CRAFT),dict(server_id=B,crafty_server_id=CRAFT,crafty_url='https://localhost:9000')]})
 def test_distinct_local_controllers_are_supported(self):
  rows=load_servers({'servers':[dict(server_id=A,crafty_server_id=CRAFT,crafty_url='https://localhost:8443'),dict(server_id=B,crafty_server_id=CRAFT,crafty_url='https://localhost:9443')]})
  self.assertEqual(len(rows),2)

class GameBookmarkTests(unittest.IsolatedAsyncioTestCase):
 async def test_game_first_link_points_to_its_own_server(self):
  from gateway import LocalBridge
  class Cloud:
   server_id=B
   def rpc(self,name,args):
    async def execute():return SimpleNamespace(data='a'*32)
    return SimpleNamespace(execute=execute)
  with tempfile.TemporaryDirectory() as root:
   bridge=LocalBridge(Cloud(),Path(root)/'bridge.db',b'k'*32)
   try:reply=await bridge.process(dict(nonce=A,operation='begin',player_uuid=CRAFT,player_name='Alex'))
   finally:bridge.close()
  self.assertIn('#server/'+B+'/linking',reply)
