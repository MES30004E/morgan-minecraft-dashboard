import {test} from 'node:test';import assert from 'node:assert/strict';
import {chartReadings,controlAvailable} from '../src/telemetry.ts';
test('charts retain missing readings instead of drawing invented zeroes',()=>{
 const points=chartReadings([{sampled_at:'2026-11-10T12:00:00Z',cpu_percent:null,memory_bytes:null},{sampled_at:'2026-11-10T12:15:00Z',cpu_percent:'0',memory_bytes:1073741824}]);
 assert.equal(points[0].cpu,null);assert.equal(points[0].memory,null);assert.equal(points[1].cpu,0);assert.equal(points[1].memory,1);
});
test('controls require fresh telemetry, host readiness, lifecycle and permission',()=>{
 assert.equal(controlAvailable('connected',false,'active',true),false);
 assert.equal(controlAvailable('unknown',true,'active',true),false);
 assert.equal(controlAvailable('connected',true,'archived',true),false);
 assert.equal(controlAvailable('connected',true,'active',false),false);
 assert.equal(controlAvailable('connected',true,'active',true),true);
});

test('unobserved time buckets remain gaps in the timeline',()=>{
 const result=chartReadings([{sampled_at:'2026-11-10T00:00:00Z',cpu_percent:10,memory_bytes:1024},{sampled_at:'2026-11-10T00:30:00Z',cpu_percent:20,memory_bytes:2048}]);
 assert.equal(result.length,3);assert.equal(result[1].cpu,null);assert.equal(result[1].memory,null);assert.equal(result[1].time,Date.parse('2026-11-10T00:15:00Z'));
});
