"""Offline archive inspection and deliberate recovery operations."""
import argparse
from getpass import getpass
import json
import os
from pathlib import Path
import sys

from archive_store import ArchiveError, LocalArchiveStore, private_read, wrap_key, unwrap_key, fsync_dir


def new_private_file(path, content):
    """Never overwrite an existing export or recovery key (including symlinks)."""
    path=Path(path)
    try: fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    except OSError as exc: raise ArchiveError('Output must be a new file in an existing directory') from exc
    with os.fdopen(fd,'wb') as stream:
        stream.write(content); stream.flush(); os.fsync(stream.fileno())
    fsync_dir(path.parent)


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path)
    parser.add_argument('--key-file',type=Path,help='Private raw 32-byte archive key, separate from bridge key')
    commands=parser.add_subparsers(dest='command',required=True)
    commands.add_parser('inspect',help='Verify and show manifests')
    commands.add_parser('health',help='Show quota usage and available disk reserve')
    search=commands.add_parser('search',help='Decrypt and search records locally; output may contain private data')
    search.add_argument('query')
    decrypt=commands.add_parser('decrypt',help='Export verified plaintext to a new 0600 file')
    decrypt.add_argument('batch_id');decrypt.add_argument('--output',type=Path,required=True)
    wrap=commands.add_parser('wrap-key',help='Create a passphrase-encrypted recovery key')
    wrap.add_argument('--output',type=Path,required=True)
    unwrap=commands.add_parser('unwrap-key',help='Recover a raw key into a new private file; never print it')
    unwrap.add_argument('--input',type=Path,required=True);unwrap.add_argument('--output',type=Path,required=True)
    mirror=commands.add_parser('mirror',help='Copy verified encrypted archives to a marked mounted target')
    mirror.add_argument('target',type=Path)
    commands.add_parser('prune',help='Expire only verified exports after their approved local TTL')
    args=parser.parse_args(argv)
    if args.command=='unwrap-key':
        key=unwrap_key(private_read(args.input),getpass('Recovery passphrase: '))
        new_private_file(args.output,key);return
    if args.key_file is None: parser.error('--key-file required')
    key=private_read(args.key_file)
    if len(key)!=32: raise ArchiveError('Archive key must be exactly 32 raw bytes')
    if args.command=='wrap-key':
        phrase=getpass('New recovery passphrase: ')
        if phrase!=getpass('Confirm recovery passphrase: '): raise ArchiveError('Passphrases differ')
        new_private_file(args.output,wrap_key(key,phrase));return
    if args.root is None: parser.error('--root required')
    store=LocalArchiveStore(args.root,key)
    if args.command=='health': print(json.dumps(store.health(),indent=2))
    elif args.command=='inspect': print(json.dumps(store.inspect(),indent=2))
    elif args.command=='search':
        for item in store.search(args.query):print(json.dumps(item,ensure_ascii=False))
    elif args.command=='decrypt':
        _,meta=store._paths(args.batch_id)
        data=store.read(store._load_manifest(meta))
        new_private_file(args.output,json.dumps(data,indent=2,ensure_ascii=False).encode()+b'\n')
    elif args.command=='mirror':print(json.dumps({'copied':store.mirror(args.target)}))
    elif args.command=='prune':print(json.dumps({'expired':store.prune()}))


if __name__=='__main__':
    try: main()
    except (ArchiveError,OSError) as exc:
        print('Archive operation refused: '+str(exc),file=sys.stderr);sys.exit(1)
