import tempfile
import unittest
from pathlib import Path
from crafty import Crafty, parse_memory, redact_log

class CraftyTests(unittest.TestCase):
    def test_remote_or_unencrypted_crafty_is_rejected(self):
        for url in ('http://localhost:8443','https://example.com','https://localhost:8443@evil.test','https://localhost:8443/a'):
            with self.assertRaises(ValueError):
                Crafty(url,'36ca5a76-35ed-4db4-aafa-d34923e83916','token','unused')

    def test_console_is_constructed_only_from_allowlisted_player_action(self):
        sent=[]
        client=Crafty.__new__(Crafty)
        client.server_id='36ca5a76-35ed-4db4-aafa-d34923e83916'
        client.request=lambda method,path,body=None: sent.append((method,path,body))
        command=dict(id='550e8400-e29b-41d4-a716-446655440000',operation='kick',arguments={'player':'Steve_123'},expires_at=200)
        client.execute(command,now=100)
        self.assertEqual(sent,[('POST','/api/v2/servers/36ca5a76-35ed-4db4-aafa-d34923e83916/stdin',b'kick Steve_123')])
        command['arguments']['player']='Steve\nstop'
        with self.assertRaises(ValueError):client.execute(command,now=100)
        self.assertEqual(len(sent),1)

    def test_memory_units_and_unknown_values(self):
        self.assertEqual(parse_memory('42.2MB'),42200000)
        self.assertEqual(parse_memory('1GiB'),1073741824)
        self.assertIsNone(parse_memory('unknown'))
        self.assertIsNone(parse_memory('-1GB'))

    def test_console_does_not_export_pairing_or_authentication_material(self):
        for line in ('Steve issued /verify abcdef012345','Authorization: Bearer sensitive','password=hello','client_secret=example'):
            self.assertEqual(redact_log(line),'[sensitive log line omitted]')
        self.assertEqual(redact_log('[INFO] Server started'),'[INFO] Server started')

if __name__=='__main__':unittest.main()
