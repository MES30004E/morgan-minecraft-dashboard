import tempfile
import unittest
from pathlib import Path
from control import Journal, validate, dispatch


class SafetyTests(unittest.TestCase):
    def test_dispatch_runs_once_and_persists_result(self):
        with tempfile.TemporaryDirectory() as directory:
            journal = Journal(Path(directory) / 'journal.db')
            calls = []
            operation = lambda command: calls.append(command['operation'])
            self.assertEqual(dispatch(journal, self.command(), operation, now=100), 'completed')
            self.assertEqual(dispatch(journal, self.command(), operation, now=100), 'completed')
            self.assertEqual(calls, ['start'])
            journal.close()

    def test_dispatch_failure_stays_uncertain_and_is_not_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            journal = Journal(Path(directory) / 'journal.db')
            calls = []
            def operation(command):
                calls.append(command)
                raise TimeoutError('Response lost after remote side effect')
            with self.assertRaises(TimeoutError):
                dispatch(journal, self.command(), operation, now=100)
            self.assertEqual(dispatch(journal, self.command(), operation, now=100), 'uncertain')
            self.assertEqual(len(calls), 1)
            journal.close()

    def command(self, **changes):
        return dict(id='550e8400-e29b-41d4-a716-446655440000', operation='start',
                    expires_at=200, arguments={}, **changes)

    def test_expired_command_rejected(self):
        with self.assertRaises(ValueError):
            validate(self.command(), now=200)

    def test_unknown_operations_rejected(self):
        command = self.command()
        for op in ['shell', 'console', 'op', 'restore', 'delete', 'start\nstop']:
            command['operation'] = op
            with self.assertRaises(ValueError):
                validate(command, now=100)

    def test_arguments_cannot_smuggle_commands(self):
        command = self.command()
        command['arguments'] = {'command': 'op attacker'}
        with self.assertRaises(ValueError):
            validate(command, now=100)

    def test_player_target_validation(self):
        command = self.command()
        command.update(operation='kick', arguments={'player': 'Steve\nstop'})
        with self.assertRaises(ValueError):
            validate(command, now=100)
        command['arguments'] = {'player': 'Steve_123'}
        self.assertEqual(validate(command, now=100)['operation'], 'kick')

    def test_replay_rejected_across_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'journal.db'
            first = Journal(path)
            self.assertTrue(first.begin(self.command()['id']))
            first.close()
            second = Journal(path)
            self.assertFalse(second.begin(self.command()['id']))
            self.assertEqual(second.state(self.command()['id']), 'uncertain')
            second.close()

    def test_completed_command_not_reexecuted(self):
        with tempfile.TemporaryDirectory() as directory:
            journal = Journal(Path(directory) / 'journal.db')
            command_id = self.command()['id']
            self.assertTrue(journal.begin(command_id))
            journal.complete(command_id)
            self.assertFalse(journal.begin(command_id))
            self.assertEqual(journal.state(command_id), 'completed')
            journal.close()

    def test_concurrent_journals_claim_once(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'journal.db'
            a, b = Journal(path), Journal(path)
            command_id = self.command()['id']
            self.assertTrue(a.begin(command_id))
            self.assertFalse(b.begin(command_id))
            a.close()
            b.close()

if __name__ == '__main__':
    unittest.main()
