"""Fail-closed operation validation and durable at-most-once dispatch journal.

The journal deliberately leaves interrupted dispatches uncertain. Reconciliation
must precede any new operation; an uncertain dispatch must never be replayed.
"""
import math
import re
import sqlite3
from uuid import UUID

OPERATIONS = frozenset({'start', 'stop', 'restart', 'kick', 'ban', 'pardon',
                        'whitelist_add', 'whitelist_remove'})
PLAYER_OPERATIONS = OPERATIONS - {'start', 'stop', 'restart'}


def dispatch(journal, command, execute, *, now):
    validated = validate(command, now=now)
    if not journal.begin(validated['id']):
        return journal.state(validated['id'])
    execute(validated)
    journal.complete(validated['id'])
    return 'completed'


def validate(command, *, now):
    if not isinstance(command, dict) or set(command) != {'id', 'operation', 'expires_at', 'arguments'}:
        raise ValueError('Invalid command envelope')
    try:
        if str(UUID(command['id'])) != command['id']:
            raise ValueError('Noncanonical command ID')
    except (ValueError, TypeError, AttributeError):
        raise ValueError('Invalid command ID') from None
    expiry = command['expires_at']
    if isinstance(expiry, bool) or not isinstance(expiry, (int, float)) or not math.isfinite(expiry) or expiry <= now:
        raise ValueError('Expired or invalid command')
    operation, arguments = command['operation'], command['arguments']
    if not isinstance(operation, str) or operation not in OPERATIONS or not isinstance(arguments, dict):
        raise ValueError('Operation not allowed')
    if operation in PLAYER_OPERATIONS:
        if set(arguments) != {'player'} or not isinstance(arguments['player'], str) or not re.fullmatch(r'[A-Za-z0-9_]{3,16}', arguments['player']):
            raise ValueError('Invalid player arguments')
    elif arguments:
        raise ValueError('Unexpected arguments')
    return {**command, 'arguments': dict(arguments)}


class Journal:
    def __init__(self, path):
        self.db = sqlite3.connect(str(path), timeout=10)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.execute('CREATE TABLE IF NOT EXISTS executions (id TEXT PRIMARY KEY, state TEXT NOT NULL CHECK(state IN (\'uncertain\', \'completed\')))')
        self.db.commit()

    def begin(self, command_id):
        with self.db:
            cursor = self.db.execute('INSERT OR IGNORE INTO executions VALUES (?, ?)', (command_id, 'uncertain'))
        return cursor.rowcount == 1

    def complete(self, command_id):
        with self.db:
            cursor = self.db.execute('UPDATE executions SET state = ? WHERE id = ? AND state = ?', ('completed', command_id, 'uncertain'))
            if cursor.rowcount != 1:
                raise ValueError('Execution was not pending')

    def state(self, command_id):
        row = self.db.execute('SELECT state FROM executions WHERE id = ?', (command_id,)).fetchone()
        return row[0] if row else None

    def close(self):
        self.db.close()
