import tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from worker import Worker
from crafty import Crafty
from control import Journal
from server_config import load_servers

class ObserveTests(unittest.IsolatedAsyncioTestCase):
 async def test_worker_is_read_only_by_default_and_never_claims(self):
  class Cloud:
   def rpc(self,*args):raise AssertionError('Read-only worker contacted command queue')
  with tempfile.TemporaryDirectory() as root:
   journal=Journal(Path(root)/'db');calls=[]
   try:self.assertFalse(await Worker(Cloud(),journal,lambda c:calls.append(c)).process_one())
   finally:journal.close()
   self.assertEqual(calls,[])
 def test_crafty_adapter_rejects_side_effects_in_observe_mode(self):
  adapter=Crafty.__new__(Crafty);adapter.read_only=True;adapter.request=lambda *args: self.fail('POST was attempted')
  with self.assertRaises(PermissionError):adapter.execute({})
 def test_control_switch_must_be_an_explicit_boolean(self):
  self.assertTrue(load_servers({'servers':[{'server_id':'11111111-1111-4111-8111-111111111111','crafty_server_id':'22222222-2222-4222-8222-222222222222','controls_enabled':True}]})[0]['controls_enabled'])
  for value in ('true',1,None):
   with self.assertRaises(ValueError):load_servers({'servers':[{'server_id':'11111111-1111-4111-8111-111111111111','crafty_server_id':'22222222-2222-4222-8222-222222222222','controls_enabled':value}]})
