import importlib.util,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('preflight',Path(__file__).resolve().parents[2]/'deploy/preflight.py')
preflight=importlib.util.module_from_spec(spec);spec.loader.exec_module(preflight)
class StageTests(unittest.TestCase):
 def test_stage_a_rejects_controls_and_integration_fields(self):
  for extra in ({'controls_enabled':True},{'upload_console':True},{'backup_directory':'/tmp/backups'},{'link_socket':'/tmp/game.sock'}):
   with self.assertRaises(ValueError):preflight.validate_stage_a([extra])
 def test_stage_a_accepts_default_observation(self):
  preflight.validate_stage_a([{'controls_enabled':False,'upload_console':False}])

 def test_existing_docker_membership_is_rejected(self):
  from types import SimpleNamespace
  account=SimpleNamespace(pw_uid=1001,pw_gid=1002,pw_dir='/var/lib/morgan-minecraft-agent',pw_shell='/usr/sbin/nologin')
  preflight.validate_service_account(account,[1002],1002)
  with self.assertRaises(ValueError):preflight.validate_service_account(account,[1002,999],1002)
