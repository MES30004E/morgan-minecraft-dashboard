import asyncio
import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from datetime import datetime, timezone
from unittest.mock import patch

from archive_store import LocalArchiveStore, ArchiveError, wrap_key, unwrap_key
from archive_worker import DailyArchiver


def batch(kind='commands', ident='batch-1', records=None):
    records = [{'id':'one','operation':'start'}] if records is None else records
    payload = json.dumps(dict(format=1,kind=kind,server_id='server',exported_at='2026-01-01T00:00:00Z',records=records))
    return dict(id=ident,kind=kind,created_at='2026-01-01T00:00:00Z',payload_text=payload,
                sha256=hashlib.sha256(payload.encode()).hexdigest(),record_count=len(records))


class Cloud:
    def __init__(self, item): self.item,self.acks,self.prepares=item,[],[]
    def rpc(self, name, args):
        cloud=self
        class Request:
            async def execute(self):
                if name=='prepare_archive':
                    cloud.prepares.append(args['kind'])
                    data=cloud.item if args['kind']=='commands' and not cloud.acks else None
                else:
                    cloud.acks.append(args);data=True
                return type('Response',(),{'data':data})()
        return Request()


def timestamp_for_test(value):
    return datetime.fromisoformat(value.replace('Z','+00:00'))


class ArchivesTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/'archives';self.key=b'K'*32
        self.store=LocalArchiveStore(self.root,self.key)

    def test_encrypted_verified_roundtrip_and_private_permissions(self):
        item=batch();manifest=self.store.store(item)
        self.assertEqual(self.store.read(manifest),json.loads(item['payload_text']))
        self.assertNotIn(b'operation', (self.root/manifest['filename']).read_bytes())
        self.assertEqual(self.root.stat().st_mode & 0o777,0o700)
        for path in self.root.iterdir():self.assertEqual(path.stat().st_mode & 0o777,0o600)
        self.assertEqual(manifest['record_count'],1)
        self.assertEqual(len(manifest['hmac']),64)

    def test_replay_reuses_verified_file_and_rejects_changed_batch(self):
        first=self.store.store(batch());before=(self.root/first['filename']).read_bytes()
        self.assertEqual(self.store.store(batch()),first)
        self.assertEqual((self.root/first['filename']).read_bytes(),before)
        with self.assertRaises(ArchiveError):self.store.store(batch(records=[]))

    def test_checksum_count_and_sensitive_keys_rejected_before_ack(self):
        bad=[]
        for field,value in [('sha256','0'*64),('record_count',9)]:
            row=batch();row[field]=value;bad.append(row)
        bad.append(batch(records=[{'nested':{'oauth_token':'secret'}}]))
        bad.append(batch(records=[{'password':'secret'}]))
        for row in bad:
            cloud=Cloud(row)
            with self.assertRaises(ArchiveError):asyncio.run(DailyArchiver(self.store).run_once(cloud))
            self.assertEqual(cloud.acks,[])

    def test_tamper_and_wrong_key_fail(self):
        manifest=self.store.store(batch());path=self.root/manifest['filename']
        with self.assertRaises(ArchiveError):LocalArchiveStore(self.root,b'X'*32).read(manifest)
        data=bytearray(path.read_bytes());data[-1]^=1;path.write_bytes(data)
        with self.assertRaises(ArchiveError):self.store.store(batch())
        with self.assertRaises(ArchiveError):self.store.prune(now='2030-01-01T00:00:00Z')
        self.assertTrue(path.exists())

    def test_manifest_tamper_prevents_reuse(self):
        self.store.store(batch());p=next(self.root.glob('*.manifest.json'))
        value=json.loads(p.read_text());value['record_count']=0;p.write_text(json.dumps(value))
        with self.assertRaises(ArchiveError):self.store.store(batch())

    def test_quota_prevents_ack_and_keeps_unknown_files(self):
        (self.root/'unknown.enc').write_bytes(b'x'*90)
        cloud=Cloud(batch())
        with self.assertRaises(ArchiveError):asyncio.run(DailyArchiver(LocalArchiveStore(self.root,self.key,max_bytes=100)).run_once(cloud))
        self.assertEqual(cloud.acks,[]);self.assertTrue((self.root/'unknown.enc').exists())

    def test_interruption_before_manifest_can_resume_without_losing_orphan(self):
        from archive_store import atomic_write
        calls=[]
        def interrupted(path,data):
            calls.append(path)
            if str(path).endswith('.manifest.json'):raise OSError('power loss')
            return atomic_write(path,data)
        with patch('archive_store.atomic_write',side_effect=interrupted):
            with self.assertRaises(OSError):self.store.store(batch())
        orphan=next(self.root.glob('*.enc'));data=orphan.read_bytes()
        manifest=self.store.store(batch())
        self.assertEqual(orphan.read_bytes(),data)
        self.assertEqual(self.store.read(manifest)['records'][0]['id'],'one')

    def test_cloud_ack_only_after_verified_archive_and_bounded_work(self):
        cloud=Cloud(batch());result=asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual(result['commands'],1)
        self.assertEqual(cloud.acks[0]['plaintext_sha'],batch()['sha256'])
        self.assertEqual(cloud.acks[0]['record_count'],1)
        self.assertEqual(cloud.prepares,['commands','commands','audit','backups','statistics','memberships'])
        class Endless(Cloud):
            def rpc(inner,name,args):
                if name=='prepare_archive':inner.acks=[]
                return super().rpc(name,args)
        endless=Endless(batch());self.assertEqual(asyncio.run(DailyArchiver(self.store).run_once(endless))['commands'],20)

    def test_ttl_prunes_only_verified_expired_archives(self):
        with patch('archive_store.datetime') as clock:
            clock.now.return_value=datetime(2026,1,1,tzinfo=timezone.utc)
            clock.fromisoformat.side_effect=datetime.fromisoformat
            self.store.store(batch());self.store.store(batch('audit','audit-1'))
        for ident in ['batch-1','audit-1']:
            with self.store.acknowledgement(ident):pass
        unknown=self.root/'unknown.enc';unknown.write_bytes(b'orphan')
        self.assertEqual(self.store.prune(now='2027-02-01T00:00:00Z'),1)
        self.assertTrue(unknown.exists());self.assertEqual(len(self.store.inspect()),1)

    def test_old_cloud_batch_uses_local_retention_clock_and_pending_never_pruned(self):
        manifest=self.store.store(batch())
        self.assertEqual(manifest['ack_state'],'pending')
        self.assertGreater(timestamp_for_test(manifest['archived_at']),timestamp_for_test('2026-01-01T00:00:00Z'))
        self.assertEqual(self.store.prune(now='2040-01-01T00:00:00Z'),0)
        with self.store.acknowledgement('batch-1'):pass
        self.assertEqual(self.store.prune(now='2026-11-11T00:00:00Z'),0)
        self.assertEqual(self.store.prune(now='2040-01-01T00:00:00Z'),1)

    def test_concurrent_prune_cannot_remove_file_during_cloud_ack(self):
        store=self.store
        class PruningCloud(Cloud):
            def rpc(inner,name,args):
                original=super().rpc(name,args)
                if name!='ack_archive':return original
                class Request:
                    async def execute(self):
                        try:store.prune(now='2040-01-01T00:00:00Z')
                        except ArchiveError:pass # busy maintenance fails closed
                        if not (store.root/'batch-1.enc').exists():raise AssertionError('Prune removed in-flight export')
                        return await original.execute()
                return Request()
        cloud=PruningCloud(batch());asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual(self.store.inspect()[0]['ack_state'],'acknowledged')
        # A formerly acknowledged archive is protected again during replay.
        cloud=PruningCloud(batch());asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertTrue((self.root/'batch-1.enc').exists())

    def test_pending_ack_recovery_when_cloud_no_longer_prepares_batch(self):
        from archive_store import atomic_write
        cloud=Cloud(batch())
        def fail_ack_state(path,data):
            if str(path).endswith('.manifest.json') and json.loads(data).get('ack_state')=='acknowledged':
                raise OSError('power loss after successful cloud ACK')
            atomic_write(path,data)
        with patch('archive_store.atomic_write',side_effect=fail_ack_state):
            with self.assertRaises(OSError):asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual(len(cloud.acks),1)
        self.assertEqual(self.store.prune(now='2040-01-01T00:00:00Z'),0)
        # Cloud source deletion committed, so prepare now returns no batch.
        resumed=Cloud(None)
        result=asyncio.run(DailyArchiver(self.store).run_once(resumed))
        self.assertEqual(len(resumed.acks),1)
        self.assertEqual(result['commands'],1)
        self.assertEqual(self.store.inspect()[0]['ack_state'],'acknowledged')

    def test_legacy_manifest_defaults_pending_and_is_not_pruned(self):
        manifest=self.store.store(batch())
        manifest.pop('archived_at',None);manifest.pop('ack_state',None)
        manifest['hmac']=self.store._sign(manifest)
        path=self.root/'batch-1.manifest.json';path.write_text(json.dumps(manifest))
        self.assertEqual(self.store.prune(now='2040-01-01T00:00:00Z'),0)
        self.assertEqual(len(self.store.pending()),1)

    def test_recovery_wrap_authenticates_passphrase(self):
        blob=wrap_key(self.key,'correct horse battery staple')
        self.assertNotIn(self.key,blob)
        self.assertEqual(unwrap_key(blob,'correct horse battery staple'),self.key)
        with self.assertRaises(ArchiveError):unwrap_key(blob,'wrong')

    def test_mirror_requires_marker_and_verifies_copy(self):
        manifest=self.store.store(batch());target=Path(self.tmp.name)/'WD';target.mkdir()
        with self.assertRaises(ArchiveError):self.store.mirror(target)
        (target/'.morgan-archive-target').write_text('morgan-minecraft-archives-v1\n')
        with patch('archive_store.os.path.ismount',return_value=True):
            self.assertEqual(self.store.mirror(target),1)
        self.assertEqual(LocalArchiveStore(target/'archives',self.key).read(manifest)['kind'],'commands')

    def test_mirror_rejects_marker_without_actual_mount(self):
        target=Path(self.tmp.name)/'WD';target.mkdir()
        (target/'.morgan-archive-target').write_text('morgan-minecraft-archives-v1')
        with patch('archive_store.os.path.ismount',return_value=False):
            with self.assertRaises(ArchiveError):self.store.mirror(target)

    def test_usage_and_free_space_reserve_block_ack(self):
        self.store.store(batch())
        self.assertGreater(self.store.usage_bytes(),0)
        health=self.store.health()
        self.assertEqual(health['used_bytes'],self.store.usage_bytes())
        self.assertEqual(health['max_bytes'],1073741824)
        self.assertEqual(health['reserve_bytes'],67108864)
        cloud=Cloud(batch(ident='new-batch'))
        low=type('Usage',(),{'free':1024})()
        with patch('archive_store.shutil.disk_usage',return_value=low):
            with self.assertRaises(ArchiveError):asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual(cloud.acks,[])
        self.assertFalse((self.root/'new-batch.enc').exists())

    def test_recognizable_credentials_rejected_in_values(self):
        for value in ['GOCSPX-abc123','sb_secret_123','Bearer secret','eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature']:
            with self.assertRaises(ArchiveError):self.store.store(batch(records=[{'description':value}]))

    def test_directory_sync_failure_prevents_cloud_ack(self):
        cloud=Cloud(batch())
        with patch('archive_store.fsync_dir',side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual(cloud.acks,[])

    def test_replay_syncs_directory_before_ack_after_uncertain_prior_sync(self):
        self.store.store(batch());cloud=Cloud(batch())
        with patch('archive_store.fsync_dir',side_effect=OSError('directory sync unavailable')):
            with self.assertRaises(OSError):asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual(cloud.acks,[])

    def test_ack_network_failure_reuses_durable_archive(self):
        class FailingAck(Cloud):
            def rpc(inner,name,args):
                if name=='ack_archive':
                    class Request:
                        async def execute(self):raise OSError('network interrupted')
                    return Request()
                return super().rpc(name,args)
        with self.assertRaises(OSError):asyncio.run(DailyArchiver(self.store).run_once(FailingAck(batch())))
        manifest=self.store.inspect()[0];original=(self.root/manifest['filename']).read_bytes()
        cloud=Cloud(batch());asyncio.run(DailyArchiver(self.store).run_once(cloud))
        self.assertEqual((self.root/manifest['filename']).read_bytes(),original)
        self.assertEqual(len(cloud.acks),1)

    def test_symlink_destination_and_credential_variants_rejected(self):
        outside=Path(self.tmp.name)/'outside';outside.write_bytes(b'do not overwrite')
        (self.root/'batch-1.enc').symlink_to(outside)
        with self.assertRaises(ArchiveError):self.store.store(batch())
        self.assertEqual(outside.read_bytes(),b'do not overwrite')
        for key in ['access_token','service_role_key','api-key','refreshToken','cookie','token']:
            with self.assertRaises(ArchiveError):self.store.store(batch(ident='sensitive-'+key.replace('_','').replace('-',''),records=[{key:'sensitive'}]))

    def test_cli_inspect_search_export_and_recovery(self):
        from archive_cli import main
        from contextlib import redirect_stdout
        import io
        manifest=self.store.store(batch())
        keyfile=Path(self.tmp.name)/'key';keyfile.write_bytes(self.key);keyfile.chmod(0o600)
        args=['--root',str(self.root),'--key-file',str(keyfile)]
        output=io.StringIO()
        with redirect_stdout(output):main(args+['inspect'])
        self.assertIn('batch-1',output.getvalue())
        with redirect_stdout(io.StringIO()) as output:main(args+['search','start'])
        self.assertIn('operation',output.getvalue())
        export=Path(self.tmp.name)/'export.json'
        main(args+['decrypt','batch-1','--output',str(export)])
        self.assertEqual(json.loads(export.read_text())['kind'],'commands')
        self.assertEqual(export.stat().st_mode & 0o777,0o600)
        with self.assertRaises(ArchiveError):main(args+['decrypt','batch-1','--output',str(export)])
        wrapped=Path(self.tmp.name)/'recovery'
        with patch('archive_cli.getpass',return_value='a long passphrase'):
            main(args+['wrap-key','--output',str(wrapped)])
        restored=Path(self.tmp.name)/'restored-key'
        with patch('archive_cli.getpass',return_value='a long passphrase'):
            main(['unwrap-key','--input',str(wrapped),'--output',str(restored)])
        self.assertEqual(restored.read_bytes(),self.key)

if __name__=='__main__':unittest.main()
