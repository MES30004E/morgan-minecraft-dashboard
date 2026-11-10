import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from backups import scan_backups

class BackupTests(unittest.TestCase):
    def test_only_complete_older_regular_archives_are_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            good=root/'world-2026.zip'
            with zipfile.ZipFile(good,'w') as archive:archive.writestr('world/level.dat',b'test fixture')
            os.utime(good,(100,100))
            (root/'incomplete.zip').write_bytes(b'PK broken')
            os.utime(root/'incomplete.zip',(100,100))
            (root/'alias.zip').symlink_to(good)
            result=scan_backups(root,now=200)
            self.assertEqual(len(result),1)
            self.assertEqual(result[0]['size_bytes'],good.stat().st_size)
            self.assertEqual(len(result[0]['backup_id']),64)
            self.assertNotIn('world-2026',str(result))
            self.assertEqual(scan_backups(root,now=150),[])
