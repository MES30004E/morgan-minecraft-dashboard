import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectionState, formatDuration } from '../src/domain.ts';
test('missing and stale heartbeats never imply an offline Minecraft server',()=>{
 assert.equal(connectionState(null,100000),'unknown');
 assert.equal(connectionState(new Date(0).toISOString(),100000),'disconnected');
 assert.equal(connectionState(new Date(99000).toISOString(),100000),'connected');
 assert.equal(connectionState('bad timestamp',100000),'unknown');
});
test('duration reports unavailable data instead of invented playtime',()=>{
 assert.equal(formatDuration(null),'Unavailable');
 assert.equal(formatDuration(3661),'1h 1m');
 assert.equal(formatDuration(0),'0m');
 assert.equal(formatDuration(-1),'Unavailable');
});
