import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseServerRoute,serverRoute,chooseServer,serverTables,authReturnRoute} from '../src/servers.ts';
const a='11111111-1111-4111-8111-111111111111',b='22222222-2222-4222-8222-222222222222';
test('bookmarks preserve server and view; invalid routes cannot select a server',()=>{
 assert.deepEqual(parseServerRoute(serverRoute(a,'players')),{serverId:a,view:'players'});
 assert.deepEqual(parseServerRoute('#server/'+b+'/player/'+a),{serverId:b,view:'player/'+a});
 assert.equal(parseServerRoute('#server/not-a-uuid/access'),null);
 assert.equal(parseServerRoute('#servers'),null);
});
test('remembered selection must still be in the permitted server list',()=>{
 assert.equal(chooseServer([a,b],b),b);assert.equal(chooseServer([a],b),a);assert.equal(chooseServer([],a),null);
});

test('heartbeats do not refetch role configuration, console or audit history',()=>{
 assert.deepEqual(serverTables('console',false),['snapshots','agent_health']);
 assert.deepEqual(serverTables('players',false),['snapshots','agent_health','online_players']);
 assert.ok(serverTables('activity',true).includes('audit_events'));
 assert.ok(serverTables('access',true).includes('permissions'));
 assert.ok(!serverTables('access',false).includes('permissions'));
});

test('Google OAuth return restores only a valid server bookmark',()=>{
 const bookmark=serverRoute(b,'linking');
 assert.equal(authReturnRoute('',bookmark),bookmark);
 assert.equal(authReturnRoute(serverRoute(a),bookmark),serverRoute(a));
 assert.equal(authReturnRoute('','javascript:alert(1)'),null);
 assert.equal(authReturnRoute('','#server/not-a-uuid/access'),null);
});
