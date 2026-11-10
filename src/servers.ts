const uuid='[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
export function parseServerRoute(hash:string):{serverId:string;view:string}|null{
 const match=hash.match(new RegExp('^#server/('+uuid+')/(overview|linking|players|console|backups|activity|access|configuration|player/'+uuid+')$','i'));
 return match?{serverId:match[1].toLowerCase(),view:match[2]}:null;
}
export function serverRoute(serverId:string,view='overview'):string{return '#server/'+serverId+'/'+view;}
export function chooseServer(permitted:string[],remembered:string|null):string|null{return remembered&&permitted.includes(remembered)?remembered:permitted[0]||null;}
