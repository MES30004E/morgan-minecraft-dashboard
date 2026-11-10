export function connectionState(heartbeat: string|null, now=Date.now()): 'unknown'|'connected'|'disconnected' {
 if (!heartbeat || !Number.isFinite(Date.parse(heartbeat))) return 'unknown';
 return now-Date.parse(heartbeat)>90_000 ? 'disconnected' : 'connected';
}
export function formatDuration(seconds: number|null): string {
 if (seconds===null || !Number.isFinite(seconds) || seconds<0) return 'Unavailable';
 const minutes=Math.floor(seconds/60);
 return minutes>=60 ? `${Math.floor(minutes/60)}h ${minutes%60}m` : `${minutes}m`;
}
