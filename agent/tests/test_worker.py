import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from control import Journal
from worker import Worker

class Cloud:
    def __init__(self, rows):self.rows=rows;self.results=[]
    def rpc(self,name,params=None):
        async def execute():
            if name=='claim_command':return SimpleNamespace(data=self.rows)
            self.results.append((name,params));return SimpleNamespace(data=None)
        return SimpleNamespace(execute=execute)

class WorkerTests(unittest.IsolatedAsyncioTestCase):
    def row(self):return dict(id='550e8400-e29b-41d4-a716-446655440000',operation='start',arguments={},expires_at='2099-01-01T00:00:00+00:00',claim_token='token')
    async def test_duplicate_claim_does_not_repeat_side_effect(self):
        with tempfile.TemporaryDirectory() as directory:
            cloud=Cloud([self.row()]);calls=[]
            worker=Worker(cloud,Journal(Path(directory)/'db'),lambda command:calls.append(command))
            await worker.process_one();await worker.process_one()
            self.assertEqual(len(calls),1)
            self.assertEqual(cloud.results[-1][1]['outcome'],'completed')
            worker.journal.close()

    async def test_lost_response_becomes_uncertain_without_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            cloud=Cloud([self.row()]);calls=[]
            def execute(command):calls.append(command);raise TimeoutError()
            worker=Worker(cloud,Journal(Path(directory)/'db'),execute)
            await worker.process_one();await worker.process_one()
            self.assertEqual(len(calls),1)
            self.assertEqual(cloud.results[-1][1]['outcome'],'uncertain')
            worker.journal.close()

    async def test_expired_claim_is_never_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            row=self.row();row['expires_at']='2000-01-01T00:00:00+00:00';calls=[]
            cloud=Cloud([row]);worker=Worker(cloud,Journal(Path(directory)/'db'),lambda c:calls.append(c))
            await worker.process_one()
            self.assertEqual(calls,[])
            self.assertEqual(cloud.results[-1][1]['outcome'],'failed')
            worker.journal.close()
