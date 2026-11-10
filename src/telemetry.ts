export type Reading={sampled_at:string;cpu_percent:number|string|null;memory_bytes:number|string|null};
export function chartReadings(rows:Reading[]){
 const points=rows.filter(row=>Number.isFinite(Date.parse(row.sampled_at))).map(row=>({time:Date.parse(row.sampled_at),cpu:row.cpu_percent===null||!Number.isFinite(Number(row.cpu_percent))?null:Number(row.cpu_percent),memory:row.memory_bytes===null||!Number.isFinite(Number(row.memory_bytes))?null:Number(row.memory_bytes)/1024**3})).sort((a,b)=>a.time-b.time);
 const result:typeof points=[];
 for(const point of points){const previous=result.at(-1);if(previous)for(let time=previous.time+900000;time<point.time&&time<=previous.time+86400000;time+=900000)result.push({time,cpu:null,memory:null});result.push(point);}
 return result;
}
export function controlAvailable(connection:string,ready:boolean,lifecycle:string,permitted:boolean){return connection==='connected'&&ready&&lifecycle==='active'&&permitted;}
