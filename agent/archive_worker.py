"""Bounded prepare → verified durable archive → cloud acknowledgement cycle."""
from archive_store import KINDS, ArchiveError

class DailyArchiver:
    def __init__(self, store): self.store=store

    async def _acknowledge(self, cloud, batch_id):
        # Hold the local lock across network I/O: even a previously acknowledged
        # archive reaching its TTL cannot be pruned during this exchange.
        with self.store.acknowledgement(batch_id) as manifest:
            await cloud.rpc('ack_archive',dict(batch_id=manifest['batch_id'],plaintext_sha=manifest['sha256'],record_count=manifest['record_count'],ciphertext_sha=manifest['cipher_sha256'])).execute()

    async def run_once(self, cloud):
        summary={kind:0 for kind in KINDS}
        # A cloud ACK can commit before its response or our local state update.
        # Retry durable pending exports even when prepare no longer returns them.
        pending=self.store.pending()
        for kind in KINDS:
            for manifest in [m for m in pending if m['kind']==kind][:20]:
                await self._acknowledge(cloud,manifest['batch_id'])
                summary[kind]+=1
        for kind in KINDS:
            for _ in range(20-summary[kind]):
                response=await cloud.rpc('prepare_archive', {'kind':kind}).execute()
                batch=response.data
                if isinstance(batch,list):
                    if len(batch)>1: raise ArchiveError('Unexpected archive batch response')
                    batch=batch[0] if batch else None
                if batch is None: break
                if batch.get('kind')!=kind: raise ArchiveError('Cloud returned wrong archive kind')
                manifest=self.store.store(batch)
                await self._acknowledge(cloud,manifest['batch_id'])
                summary[kind]+=1
        return summary
