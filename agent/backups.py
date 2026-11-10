"""Read-only metadata for existing ZIP archives; never creates/restores backups."""
import hashlib
import stat
import struct
import time
import zipfile
from datetime import datetime,timezone
from pathlib import Path

def scan_backups(directory,*,now=None):
    now=time.time() if now is None else now
    candidates=[]
    for path in Path(directory).iterdir():
        info=path.lstat()
        if path.suffix.lower()!='.zip' or not stat.S_ISREG(info.st_mode) or not 60<=now-info.st_mtime<=90*86400:
            continue
        candidates.append((info.st_mtime,path,info))
    result=[]
    for _,path,info in sorted(candidates,reverse=True)[:120]:
        try:
            # Bound metadata parsing without decompressing Minecraft backup contents.
            with path.open('rb') as archive:
                archive.seek(max(0,info.st_size-65557));tail=archive.read(65557)
            end=tail.rfind(b'PK\x05\x06')
            if end<0 or len(tail)-end<22:continue
            count=struct.unpack_from('<H',tail,end+10)[0]
            directory_size=struct.unpack_from('<I',tail,end+12)[0]
            if count>50000 or directory_size>4*1024*1024:continue
            with zipfile.ZipFile(path) as archive:archive.infolist()
            after=path.lstat()
            if after.st_size!=info.st_size or after.st_mtime_ns!=info.st_mtime_ns:continue
            result.append(dict(backup_id=hashlib.sha256((path.name+str(info.st_mtime_ns)).encode()).hexdigest(),
                               created_at=datetime.fromtimestamp(info.st_mtime,timezone.utc).isoformat(),size_bytes=info.st_size))
        except (OSError,zipfile.BadZipFile,struct.error):continue
    return result
