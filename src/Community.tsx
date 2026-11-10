import {useEffect,useRef,useState} from 'react';
import {supabase} from './client';
import {connectionState,formatDuration} from './domain';
import {Linking} from './Linking';
import {Statistics} from './Statistics';
import {serverRoute} from './servers';
import {ServerConfiguration,type GameServer,type Endpoint} from './ServerConfiguration';
type Row=Record<string,any>;
export function Community({userId,server,view,endpoints,onConfigurationChange}:{userId:string;server:GameServer;view:string;endpoints:Endpoint[];onConfigurationChange:()=>void}){
 const SERVER=server.id,tab=view;
 const [data,setData]=useState<Record<string,Row[]>>({});
 const [message,setMessage]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true),[clock,setClock]=useState(Date.now());
 const retry=useRef<{signature:string;id:string}|null>(null);
 async function load(details=true){
  const tables=['servers','memberships','roles','role_permissions','snapshots','agent_health'];
  if(details){if(tab==='players'||tab.startsWith('player/'))tables.push('online_players','player_statistics');if(tab==='console')tables.push('console_tail');if(tab==='backups')tables.push('backups');if(tab==='activity')tables.push('commands','audit_events');}
  else if(tab==='players')tables.push('online_players');
  const results=await Promise.all(tables.map(t=>{
   let query=supabase.from(t).select('*');
   if(t==='servers')query=query.eq('id',SERVER);else if(t!=='role_permissions')query=query.eq('server_id',SERVER);
   if(t==='commands'||t==='audit_events')query=query.order('created_at',{ascending:false}).limit(50);
   if(t==='backups')query=query.order('created_at',{ascending:false}).limit(30);
   if(t==='player_statistics')query=query.order('play_time_ticks',{ascending:false}).limit(100);
   return query;
  }));
  const failed=results.find(r=>r.error);if(failed?.error)throw failed.error;
  setData(previous=>({...previous,...Object.fromEntries(tables.map((t,i)=>[t,results[i].data||[]]))}));setLoading(false);setClock(Date.now());
 }
 useEffect(()=>{
  let active=true;const update=()=>{if(active)load(false).catch(e=>{setLoading(false);setMessage(e.message);});};
  load().catch(e=>{setLoading(false);setMessage(e.message);});
  // Visible pages subscribe to bounded snapshot and command events; no request polling.
  let channel:ReturnType<typeof supabase.channel>|null=null;
  const visibility=()=>{
   if(channel){supabase.removeChannel(channel);channel=null;}
   if(document.visibilityState==='visible'){
    update();channel=supabase.channel('server-'+SERVER).on('postgres_changes',{event:'*',schema:'public',table:'snapshots',filter:'server_id=eq.'+SERVER},update)
     .on('postgres_changes',{event:'*',schema:'public',table:'commands',filter:'server_id=eq.'+SERVER},update).subscribe(status=>{if(status==='CHANNEL_ERROR'||status==='TIMED_OUT')setMessage('Live connection interrupted. Refresh to retry.');});
   }
  };
  visibility();document.addEventListener('visibilitychange',visibility);
  const timer=setInterval(()=>setClock(Date.now()),15_000);
  return()=>{active=false;document.removeEventListener('visibilitychange',visibility);clearInterval(timer);if(channel)supabase.removeChannel(channel);};
 },[userId,SERVER,tab]);
 const membership=data.memberships?.find(m=>m.user_id===userId),role=data.roles?.find(r=>r.id===membership?.role_id);
 const permissions=new Set(data.role_permissions?.filter(p=>p.role_id===membership?.role_id).map(p=>p.permission));
 const allowed=(permission:string)=>membership?.state==='approved'&&permissions.has(permission);
 const archiveHealth=data.agent_health?.[0];
 const snapshot=data.snapshots?.[0],connection=connectionState(snapshot?.heartbeat_at||null,clock);
 async function run(work:()=>Promise<void>){setBusy(true);setMessage('');try{await work();await load();}catch(e){setMessage(e instanceof Error?e.message:String((e as Row)?.message||'Request failed'));}finally{setBusy(false);}}
 async function rpc(name:string,args:Row){const {error}=await supabase.rpc(name,args);if(error)throw error;}
 async function command(operation:string,args:Row={}){
  const signature=JSON.stringify({operation,args});if(retry.current?.signature!==signature)retry.current={signature,id:crypto.randomUUID()};
  const request=retry.current;
  await run(async()=>{await rpc('enqueue_command',{target:SERVER,action:operation,args,request_id:request!.id});retry.current=null;setMessage('Command queued. Results appear in Activity.');});
 }
 if(loading)return <section aria-busy="true">Loading server access…</section>;
 return <div className="community"><div className="server-heading"><div><div className="eyebrow">YOUR SERVER</div><h2>{server.icon} {server.name}</h2></div><span className="badge">{role?.name||membership?.state||'NOT ENROLLED'}</span></div>
 <nav className="tabs" aria-label="Server views">{['overview','linking','players','console','backups','activity','access',...(allowed('server.configure')?['configuration']:[])].map(name=><a key={name} href={serverRoute(SERVER,name)} aria-current={tab===name?'page':undefined}>{name[0].toUpperCase()+name.slice(1)}</a>)}</nav>
 {message&&<div className="notice" role="status">{message}</div>}
 {allowed('audit.view')&&archiveHealth&&(archiveHealth.archive_state==='failed'||archiveHealth.archive_state==='disabled'||archiveHealth.archive_bytes/archiveHealth.quota_bytes>0.8||archiveHealth.disk_free_bytes<104857600)&&<div className="notice" role="status">Local archives: {archiveHealth.archive_state}. Storage {archiveHealth.archive_bytes!=null?(archiveHealth.archive_bytes/1024**2).toFixed(1)+' MiB':'unavailable'}. Check archive health before the storage reserve is exhausted. Cloud copies without a verified archive are retained.</div>}
 {tab==='linking'?<Linking userId={userId} serverId={SERVER}/>:membership?.state!=='approved'?<section><h2>{membership?'Approval pending':'Join the community'}</h2><p>{membership?'Membership state: '+membership.state:'Request access to begin registration. Minecraft identity verification is a separate step.'}</p>{!membership&&<button className="primary" disabled={busy} onClick={()=>run(()=>rpc('request_membership',{target:SERVER}))}>Request membership</button>}</section>:
 <>{tab==='configuration'&&(allowed('server.configure')?<ServerConfiguration server={server} endpoints={endpoints} onChange={onConfigurationChange}/>:<section>Configuration access is restricted.</section>)}{tab==='overview'&&<><div className="metric-grid"><section><small>SERVER STATE</small><strong>{connection==='connected'?snapshot?.state||'Unknown':'Unknown'}</strong><p>Agent {connection}</p></section><section><small>CPU</small><strong>{connection==='connected'&&snapshot?.cpu_percent!=null?snapshot.cpu_percent+'%':'—'}</strong></section><section><small>MEMORY</small><strong>{connection==='connected'&&snapshot?.memory_bytes!=null?(snapshot.memory_bytes/1024**3).toFixed(2)+' GiB':'—'}</strong></section><section><small>UPTIME</small><strong>{connection==='connected'?formatDuration(snapshot?.uptime_seconds??null):'Unavailable'}</strong></section></div><section><h2>Server controls</h2><p>{connection==='connected'?'Operations run through the secure command queue.':'The Ubuntu agent has not reported a recent heartbeat. Controls become available when it reconnects.'}</p><div className="actions">{['start','stop','restart'].filter(a=>allowed('server.'+a)).map(action=><button key={action} disabled={busy||connection!=='connected'||server.lifecycle!=='active'} onClick={()=>{if(action!=='start'&&!confirm(`${action} ${server.name}? Connected players will be disconnected.`))return;command(action);}}>{action[0].toUpperCase()+action.slice(1)}</button>)}</div>{endpoints.length?endpoints.map(e=><p className="address" key={e.id}>{e.hostname}{e.public_port?':'+e.public_port:''} · {e.provider} · Connection {e.connection_state}</p>):<p>No public endpoint listed for this server.</p>}</section></>}
 {(tab==='players'||tab.startsWith('player/'))&&<section><h2>Online players</h2>{!allowed('players.view')?<p>You do not have player-list permission.</p>:connection!=='connected'?<p>Player presence is unavailable while the agent is disconnected.</p>:data.online_players?.[0]?.players?.length?<ul>{data.online_players[0].players.map((p:Row)=><li key={p.uuid||p.name}>{p.name}</li>)}</ul>:<p>No online players reported.</p>}{['kick','ban','pardon','whitelist_add','whitelist_remove'].some(a=>allowed('players.'+a))&&<form onSubmit={event=>{event.preventDefault();const values=new FormData(event.currentTarget);if(confirm('Submit this player management operation?'))command(String(values.get('action')),{player:String(values.get('player'))});}}><label>Minecraft username<input name="player" pattern="[A-Za-z0-9_]{3,16}" minLength={3} maxLength={16} required/></label><label>Approved operation<select name="action">{['kick','ban','pardon','whitelist_add','whitelist_remove'].filter(a=>allowed('players.'+a)).map(a=><option key={a} value={a}>{a.replaceAll('_',' ')}</option>)}</select></label><button disabled={busy||connection!=='connected'||server.lifecycle!=='active'}>Submit operation</button></form>}<Statistics serverId={SERVER} players={(data.player_statistics||[]) as any} focus={tab.startsWith('player/')?tab.slice(7):undefined}/></section>}
 {tab==='console'&&<section><h2>Read-only console</h2>{allowed('console.view')?<><p>Last uploaded: {data.console_tail?.[0]?.updated_at?new Date(data.console_tail[0].updated_at).toLocaleString():'No logs received'}</p><pre>{data.console_tail?.[0]?.lines?.join('\n')||'Console unavailable until the agent connects.'}</pre></>:<p>Console access is restricted.</p>}</section>}
 {tab==='backups'&&<section><h2>Backup history</h2>{!allowed('backups.view')?<p>Backup visibility is restricted.</p>:data.backups?.length?<ul>{data.backups.map(b=><li key={b.backup_id}>{new Date(b.created_at).toLocaleString()} · {b.state}</li>)}</ul>:<p>No backup metadata has been uploaded. Existing Crafty backup schedules continue independently.</p>}</section>}
 {tab==='activity'&&<section><h2>Command activity</h2>{data.commands?.length?<ul>{data.commands.map(c=><li key={c.id}>{new Date(c.created_at).toLocaleString()} · {c.operation} · <strong>{c.state}</strong>{c.result&&<p>{c.result}</p>}{c.state==='uncertain'&&allowed('access.manage')&&<form onSubmit={event=>{event.preventDefault();const values=new FormData(event.currentTarget);if(confirm('Confirm you inspected Crafty or the server console and verified this outcome. This records reconciliation; it does not run the command again.'))run(()=>rpc('resolve_uncertain',{command_id:c.id,outcome:String(values.get('outcome')),note:String(values.get('note'))}));}}><label>Verified outcome<select name="outcome"><option value="completed">Crafty accepted the operation</option><option value="failed">Operation did not complete</option></select></label><label>What did you verify?<input name="note" minLength={10} maxLength={1000} required/></label><button disabled={busy}>Record reconciliation</button></form>}</li>)}</ul>:<p>No commands to display.</p>}{allowed('audit.view')&&<><h2>Audit history</h2><ul>{data.audit_events?.map(a=><li key={a.id}>{new Date(a.created_at).toLocaleString()} · {a.action}</li>)}</ul></>}</section>}
 {tab==='access'&&<section><h2>Membership & permissions</h2>{!allowed('access.manage')?<p>Your role: {role?.name||'None'}. Contact the owner to change your access.</p>:<><p>Approval and role assignment are enforced by the database. Your own role cannot be changed here.</p>{data.memberships?.map(m=><form key={m.user_id} className="member-row" onSubmit={event=>{event.preventDefault();const values=new FormData(event.currentTarget);run(()=>rpc('manage_member',{target:SERVER,person:m.user_id,new_state:String(values.get('state')),new_role:String(values.get('role'))}));}}><code>{m.user_id===userId?'You':m.user_id}</code><select name="state" defaultValue={m.state} aria-label={'Approval for '+m.user_id}>{['pending','approved','rejected','suspended'].map(s=><option key={s}>{s}</option>)}</select><select name="role" defaultValue={m.role_id||data.roles?.find(r=>r.name==='Member')?.id} aria-label={'Role for '+m.user_id}>{data.roles?.map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select><button disabled={busy||m.user_id===userId}>Save access</button></form>)}<h2>Configure role permissions</h2><form onSubmit={event=>{event.preventDefault();const values=new FormData(event.currentTarget);run(()=>rpc('set_role_permission',{target:SERVER,target_role:String(values.get('role')),capability:String(values.get('permission')),enabled:values.get('enabled')==='on'}));}}><label>Role<select name="role">{data.roles?.filter(r=>r.id!==membership?.role_id).map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select></label><label>Permission<select name="permission">{['status.view','players.view','server.start','server.stop','server.restart','players.kick','players.ban','players.pardon','players.whitelist_add','players.whitelist_remove','console.view','backups.view','audit.view','access.manage'].map(p=><option key={p}>{p}</option>)}</select></label><label className="check"><input name="enabled" type="checkbox"/>Grant this permission</label><button disabled={busy}>Update permission</button></form></>}</section>}
 </>}
 <button className="refresh" disabled={busy} onClick={()=>run(()=>load())}>Refresh server data</button></div>;
}
