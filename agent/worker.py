"""Cloud claim → durable journal → local allowlist → fenced acknowledgement."""
import asyncio
import time
from datetime import datetime
from control import validate

class Worker:
    def __init__(self, cloud, journal, execute):
        self.cloud,self.journal,self.execute=cloud,journal,execute

    async def process_one(self):
        response=await self.cloud.rpc('claim_command',{}).execute()
        if not response.data:return False
        row=response.data[0]
        try:
            command=dict(id=row['id'],operation=row['operation'],arguments=row['arguments'],
                         expires_at=datetime.fromisoformat(row['expires_at'].replace('Z','+00:00')).timestamp())
            validate(command,now=time.time())
        except (ValueError,TypeError,KeyError):
            outcome,summary='failed','Invalid or expired command rejected before dispatch'
        else:
            try:
                # SQLite stays on its creating thread; only network I/O is offloaded.
                if self.journal.begin(command['id']):
                    await asyncio.to_thread(self.execute,command)
                    self.journal.complete(command['id'])
                outcome=self.journal.state(command['id'])
                summary='Accepted by Crafty' if outcome=='completed' else 'Manual reconciliation required; no replay attempted'
            except Exception:
                outcome,summary='uncertain','Dispatch interrupted; inspect Crafty before reconciling'
        await self.cloud.rpc('finish_command',dict(command_id=row['id'],token=row['claim_token'],outcome=outcome,summary=summary)).execute()
        return True
