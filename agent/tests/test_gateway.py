import base64
import hashlib
import hmac
import json
import unittest
import tempfile
from pathlib import Path
from types import SimpleNamespace
from gateway import decode_message, encode_message, LocalBridge

class GatewayTests(unittest.TestCase):
    def message(self,**changes):
        value=dict(nonce='550e8400-e29b-41d4-a716-446655440000',issued_at=100,operation='profile',player_uuid='550e8400-e29b-41d4-a716-446655440001',player_name='Steve',online_mode=True)
        value.update(changes)
        return encode_message(value,b'k'*32)

    def test_authentic_online_identity_accepted(self):
        self.assertEqual(decode_message(self.message(),b'k'*32,now=100)['player_name'],'Steve')

    def test_wrong_key_tampering_and_stale_messages_rejected(self):
        with self.assertRaises(ValueError):decode_message(self.message(),b'x'*32,now=100)
        with self.assertRaises(ValueError):decode_message(self.message(),b'k'*32,now=200)
        with self.assertRaises(ValueError):decode_message(self.message(online_mode=False),b'k'*32,now=100)
        with self.assertRaises(ValueError):decode_message(self.message(operation='shell'),b'k'*32,now=100)
        envelope=json.loads(self.message());envelope['payload']=base64.b64encode(b'{}').decode()
        with self.assertRaises(ValueError):decode_message(json.dumps(envelope).encode(),b'k'*32,now=100)

    def test_username_and_uuid_validation(self):
        with self.assertRaises(ValueError):decode_message(self.message(player_name='Steve\nstop'),b'k'*32,now=100)
        with self.assertRaises(ValueError):decode_message(self.message(player_uuid='Steve'),b'k'*32,now=100)

    def test_statistics_have_a_closed_schema(self):
        stats=dict(online=True,play_time_ticks=20,deaths=0,mob_kills=0,blocks_mined=2,advancements_done=1,advancements_total=10)
        self.assertEqual(decode_message(self.message(operation='stats',statistics=stats),b'k'*32,now=100)['statistics'],stats)
        stats['shell']='unsafe'
        with self.assertRaises(ValueError):decode_message(self.message(operation='stats',statistics=stats),b'k'*32,now=100)

class BridgeReplayTests(unittest.IsolatedAsyncioTestCase):
    async def test_replay_is_rejected_after_gateway_restart(self):
        class Cloud:
            def rpc(self,name,args):
                async def execute():return SimpleNamespace(data='No identity linked')
                return SimpleNamespace(execute=execute)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'journal.db'
            value=dict(nonce='550e8400-e29b-41d4-a716-446655440000',operation='profile',player_uuid='550e8400-e29b-41d4-a716-446655440001')
            first=LocalBridge(Cloud(),path,b'k'*32)
            self.assertEqual(await first.process(value),'No identity linked')
            first.close()
            second=LocalBridge(Cloud(),path,b'k'*32)
            with self.assertRaises(ValueError):await second.process(value)
            second.close()
