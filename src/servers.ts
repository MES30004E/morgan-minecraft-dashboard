const uuid='[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
export function parseServerRoute(hash:string):{serverId:string;view:string}|null{
 const match=hash.match(new RegExp('^#server/('+uuid+')/(overview|linking|players|console|backups|activity|access|configuration|player/'+uuid+')$','i'));
 return match?{serverId:match[1].toLowerCase(),view:match[2]}:null;
}
export function serverRoute(serverId:string,view='overview'):string{return '#server/'+serverId+'/'+view;}
export function chooseServer(permitted:string[],remembered:string|null):string|null{return remembered&&permitted.includes(remembered)?remembered:permitted[0]||null;}
export function serverTables(view:string,details:boolean):string[]{
 const tables=details?['servers','memberships','roles','role_permissions','snapshots','agent_health']:['snapshots','agent_health'];
 if(view==='players'||view.startsWith('player/')){tables.push('online_players');if(details)tables.push('player_statistics');}
 if(details){if(view==='access')tables.push('permissions');if(view==='console')tables.push('console_tail');if(view==='backups')tables.push('backups');if(view==='activity')tables.push('commands','audit_events');}
 return tables;
}
export function authReturnRoute(current:string,stored:string|null):string|null{
 if(current)return parseServerRoute(current)?current:null;
 return stored&&parseServerRoute(stored)?stored:null;
}
