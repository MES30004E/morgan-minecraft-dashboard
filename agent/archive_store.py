"""Authenticated local exports. No cloud acknowledgement belongs in this module."""
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import shutil
import uuid

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

KINDS = ('commands', 'audit', 'backups', 'statistics', 'memberships')
TTL_DAYS = dict(commands=365, audit=730, backups=365, statistics=365, memberships=365)
MAGIC = b'MCARCH1\0'
FREE_RESERVE_BYTES = 64 * 1024 * 1024

class ArchiveError(ValueError):
    """An archive cannot safely be accepted, read, or expired."""


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data):
    """Write private bytes and make both file content and rename durable."""
    path = Path(path)
    tmp = path.parent / ('.pending-' + uuid.uuid4().hex)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
        fsync_dir(path.parent)
    finally:
        if tmp.exists():
            tmp.unlink()


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try: os.fsync(fd)
    finally: os.close(fd)


def private_dir(path):
    path = Path(path)
    if path.is_symlink(): raise ArchiveError('Symlink archive directory rejected')
    missing=[]
    cursor=path
    while not cursor.exists():
        missing.append(cursor);cursor=cursor.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700,exist_ok=True)
        fsync_dir(directory)
        fsync_dir(directory.parent)
    if not path.is_dir(): raise ArchiveError('Archive root must be a directory')
    os.chmod(path, 0o700)


def private_read(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode): raise ArchiveError('Archive must be a regular file')
            if info.st_mode & 0o077: raise ArchiveError('Archive file permissions must be 0600')
            return stream.read()
    except OSError as exc:
        raise ArchiveError('Archive file unavailable or unsafe') from exc


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if result.tzinfo is None: raise ValueError()
        return result
    except (ValueError, TypeError, AttributeError) as exc:
        raise ArchiveError('Archive timestamp must include timezone') from exc


def reject_secrets(value):
    if isinstance(value, dict):
        for key, item in value.items():
            name = re.sub(r'[^a-z0-9]', '', key.lower())
            if any(term in name for term in ('password', 'passwd', 'oauth', 'secret', 'servicekey', 'servicerole', 'accesstoken', 'refreshtoken', 'authorization', 'apikey', 'privatekey', 'credential', 'token', 'cookie', 'session')):
                raise ArchiveError('Sensitive credential field rejected')
            reject_secrets(item)
    elif isinstance(value, list):
        for item in value: reject_secrets(item)
    elif isinstance(value, str):
        if re.search(r'(?:GOCSPX-|sb_secret_|Bearer\s+\S+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)',value,re.IGNORECASE):
            raise ArchiveError('Recognizable credential value rejected')


class LocalArchiveStore:
    def __init__(self, root: Path, key: bytes, max_bytes=1073741824):
        if not isinstance(key, bytes) or len(key) != 32: raise ArchiveError('Archive key must be 32 bytes')
        if not isinstance(max_bytes, int) or max_bytes < 1: raise ArchiveError('Invalid archive quota')
        self.root, self.key, self.max_bytes = Path(root), key, max_bytes
        self.signing_key = hmac.digest(key, b'morgan-archive-manifest-v1', 'sha256')
        private_dir(self.root)

    @contextmanager
    def _locked(self):
        fd = os.open(self.root / '.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            os.fchmod(fd, 0o600)
            try: fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc: raise ArchiveError('Archive store busy; retry later') from exc
            yield
        finally: os.close(fd)

    def usage_bytes(self):
        """Account for all regular archive-root files, including unknown/orphan files."""
        return sum(p.lstat().st_size for p in self.root.rglob('*') if p.is_file())

    def health(self):
        used=self.usage_bytes()
        free=shutil.disk_usage(self.root).free
        return dict(used_bytes=used,max_bytes=self.max_bytes,remaining_bytes=max(0,self.max_bytes-used),disk_free_bytes=free,reserve_bytes=FREE_RESERVE_BYTES,writable=used<self.max_bytes and free>FREE_RESERVE_BYTES)

    def _preflight(self, needed):
        if self.usage_bytes()+needed>self.max_bytes:
            raise ArchiveError('Archive quota exceeded; cloud acknowledgement prohibited')
        if shutil.disk_usage(self.root).free<needed+FREE_RESERVE_BYTES:
            raise ArchiveError('Insufficient disk reserve; cloud acknowledgement prohibited')

    def _sign(self, manifest):
        return hmac.new(self.signing_key, canonical({k:v for k,v in manifest.items() if k != 'hmac'}), hashlib.sha256).hexdigest()

    def _paths(self, batch_id):
        if not isinstance(batch_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', batch_id):
            raise ArchiveError('Invalid archive batch id')
        return self.root/(batch_id+'.enc'), self.root/(batch_id+'.manifest.json')

    def _validate(self, raw, kind, sha, count):
        if digest(raw) != sha: raise ArchiveError('Plaintext checksum mismatch')
        try: payload = json.loads(raw)
        except (ValueError, UnicodeError) as exc: raise ArchiveError('Invalid archive JSON') from exc
        if not isinstance(payload, dict) or payload.get('format') != 1 or payload.get('kind') != kind or kind not in KINDS:
            raise ArchiveError('Invalid archive format or kind')
        if not isinstance(payload.get('server_id'), str): raise ArchiveError('Missing server identity')
        timestamp(payload.get('exported_at'))
        records = payload.get('records')
        if not isinstance(records, list) or type(count) is not int or len(records) != count:
            raise ArchiveError('Archive record count mismatch')
        reject_secrets(payload)
        return payload

    def read(self, manifest):
        try:
            if not hmac.compare_digest(self._sign(manifest), manifest['hmac']): raise ArchiveError('Manifest authentication failed')
            path, _ = self._paths(manifest['batch_id'])
            if manifest['filename'] != path.name: raise ArchiveError('Archive filename mismatch')
            timestamp(manifest['created_at'])
            if 'archived_at' in manifest: timestamp(manifest['archived_at'])
            if manifest.get('ack_state','pending') not in ('pending','acknowledged'):
                raise ArchiveError('Invalid archive acknowledgement state')
            encrypted = private_read(path)
            if digest(encrypted) != manifest['cipher_sha256']: raise ArchiveError('Ciphertext checksum mismatch')
            if not encrypted.startswith(MAGIC): raise ArchiveError('Unknown encryption format')
            nonce = encrypted[len(MAGIC):len(MAGIC)+12]
            compressed = AESGCM(self.key).decrypt(nonce, encrypted[len(MAGIC)+12:], path.stem.encode())
            raw = gzip.decompress(compressed)
            self._validate(raw, manifest['kind'], manifest['sha256'], manifest['record_count'])
            return json.loads(raw)
        except ArchiveError: raise
        except Exception as exc: raise ArchiveError('Archive authentication or decoding failed') from exc

    def _load_manifest(self, path):
        try: return json.loads(private_read(path))
        except (ValueError, UnicodeError) as exc: raise ArchiveError('Invalid manifest JSON') from exc

    def store(self, batch: dict):
        try:
            raw = batch['payload_text'].encode('utf-8')
            self._validate(raw, batch['kind'], batch['sha256'], batch['record_count'])
            timestamp(batch['created_at'])
            path, manifest_path = self._paths(batch['id'])
        except (KeyError, AttributeError, TypeError) as exc: raise ArchiveError('Invalid batch envelope') from exc
        with self._locked():
            if manifest_path.exists():
                manifest = self._load_manifest(manifest_path)
                self.read(manifest)
                for field, source in [('batch_id','id'),('kind','kind'),('created_at','created_at'),('sha256','sha256'),('record_count','record_count')]:
                    if manifest[field] != batch[source]: raise ArchiveError('Batch identity reused for different content')
                # Re-protect previously acknowledged exports before another ACK.
                manifest.setdefault('archived_at',datetime.now(timezone.utc).isoformat())
                manifest['ack_state']='pending'
                self._write_manifest(manifest)
                fsync_dir(self.root.parent)
                return manifest
            nonce = os.urandom(12)
            encrypted = MAGIC + nonce + AESGCM(self.key).encrypt(nonce, gzip.compress(raw, mtime=0), batch['id'].encode())
            if path.exists():
                # An interrupted manifest write may leave a complete encrypted export.
                # Authenticate it before reuse; never replace an unverified orphan.
                encrypted = private_read(path)
            manifest = dict(batch_id=batch['id'],kind=batch['kind'],created_at=batch['created_at'],archived_at=datetime.now(timezone.utc).isoformat(),ack_state='pending',record_count=batch['record_count'],sha256=batch['sha256'],cipher_sha256=digest(encrypted),filename=path.name)
            manifest['hmac'] = self._sign(manifest)
            manifest_bytes = canonical(manifest)
            needed = len(manifest_bytes) + (0 if path.exists() else len(encrypted))
            self._preflight(needed)
            if not path.exists(): atomic_write(path, encrypted)
            # Re-read authenticated bytes from disk before signing durable acceptance.
            self.read(manifest)
            atomic_write(manifest_path, manifest_bytes)
            manifest = self._load_manifest(manifest_path)
            self.read(manifest)
            return manifest

    def _write_manifest(self, manifest):
        """Caller owns the store lock; persist authenticated state transitions."""
        _,meta=self._paths(manifest['batch_id'])
        manifest['hmac']=self._sign(manifest)
        data=canonical(manifest)
        existing=meta.stat().st_size if meta.exists() else 0
        self._preflight(max(0,len(data)-existing))
        atomic_write(meta,data)

    def pending(self):
        """Verify retryable exports, including legacy manifests lacking ACK state."""
        return [manifest for manifest in self.inspect() if manifest.get('ack_state','pending')=='pending']

    @contextmanager
    def acknowledgement(self, batch_id):
        """Keep prune excluded across the caller's awaited cloud ACK.

        Normal exit means cloud ACK succeeded; exceptional exit retains pending.
        Contending operations fail closed instead of blocking an async event loop.
        """
        with self._locked():
            _,meta=self._paths(batch_id)
            manifest=self._load_manifest(meta)
            self.read(manifest)
            manifest.setdefault('archived_at',datetime.now(timezone.utc).isoformat())
            manifest['ack_state']='pending'
            self._write_manifest(manifest)
            self.read(self._load_manifest(meta))
            yield manifest
            self.read(manifest)
            manifest['ack_state']='acknowledged'
            self._write_manifest(manifest)

    def inspect(self):
        result=[]
        for path in sorted(self.root.glob('*.manifest.json')):
            manifest=self._load_manifest(path); self.read(manifest); result.append(manifest)
        return result

    def search(self, query):
        for manifest in self.inspect():
            payload=self.read(manifest)
            for record in payload['records']:
                if query.casefold() in json.dumps(record, ensure_ascii=False).casefold():
                    yield dict(batch_id=manifest['batch_id'],kind=manifest['kind'],record=record)

    def prune(self, now=None):
        current=timestamp(now) if now else datetime.now(timezone.utc)
        with self._locked():
            # Validate ALL manifests before deleting ANY files.
            manifests=self.inspect()
            expired=[m for m in manifests if m.get('ack_state','pending')=='acknowledged' and 'archived_at' in m and (current-timestamp(m['archived_at'])).total_seconds() > TTL_DAYS[m['kind']]*86400]
            for manifest in expired:
                path, meta=self._paths(manifest['batch_id'])
                # Drop manifest first: an interrupted deletion leaves a retained orphan.
                meta.unlink(); fsync_dir(self.root)
                path.unlink(); fsync_dir(self.root)
            return len(expired)

    def mirror(self, target):
        target=Path(target)
        marker=target/'.morgan-archive-target'
        if target.is_symlink() or not target.is_dir() or not os.path.ismount(target) or marker.is_symlink() or not marker.is_file() or marker.read_text().strip()!='morgan-minecraft-archives-v1':
            raise ArchiveError('Explicit archive target marker required')
        destination=LocalArchiveStore(target/'archives', self.key, self.max_bytes)
        count=0
        for manifest in self.inspect():
            self.read(manifest)
            source_path=self.root/manifest['filename']
            encrypted=private_read(source_path)
            with destination._locked():
                path,meta=destination._paths(manifest['batch_id'])
                if meta.exists():
                    existing=destination._load_manifest(meta)
                    destination.read(existing)
                    immutable=lambda m:{k:v for k,v in m.items() if k not in ('hmac','ack_state')}
                    if immutable(existing)!=immutable(manifest): raise ArchiveError('Mirror has conflicting archive')
                    if existing!=manifest:destination._write_manifest(dict(manifest))
                else:
                    if path.exists() and private_read(path)!=encrypted:
                        raise ArchiveError('Mirror has unverified conflicting file')
                    needed=len(canonical(manifest))+(0 if path.exists() else len(encrypted))
                    destination._preflight(needed)
                    if not path.exists(): atomic_write(path,encrypted)
                    destination.read(manifest)
                    atomic_write(meta,canonical(manifest))
                    destination.read(destination._load_manifest(meta))
            count+=1
        return count


def wrap_key(key, passphrase):
    if len(key)!=32 or not passphrase: raise ArchiveError('Key and recovery passphrase required')
    salt,nonce=os.urandom(16),os.urandom(12)
    derived=Scrypt(salt=salt,length=32,n=2**17,r=8,p=1).derive(passphrase.encode())
    return b'MCKEY1\0'+salt+nonce+AESGCM(derived).encrypt(nonce,key,b'morgan-recovery-v1')


def unwrap_key(blob, passphrase):
    try:
        if not blob.startswith(b'MCKEY1\0') or len(blob)!=83: raise ValueError()
        salt,nonce=blob[7:23],blob[23:35]
        derived=Scrypt(salt=salt,length=32,n=2**17,r=8,p=1).derive(passphrase.encode())
        return AESGCM(derived).decrypt(nonce,blob[35:],b'morgan-recovery-v1')
    except Exception as exc: raise ArchiveError('Recovery key authentication failed') from exc
