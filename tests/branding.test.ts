import {test} from 'node:test';
import assert from 'node:assert/strict';
import {displayName} from '../src/branding.ts';
test('branding defaults to a neutral product name and accepts an explicit display name',()=>{
 assert.equal(displayName(undefined),'Minecraft Console');
 assert.equal(displayName('  Community Panel  '),'Community Panel');
 assert.equal(displayName('   '),'Minecraft Console');
 assert.equal(displayName('x'.repeat(81)),'Minecraft Console');
 assert.equal(displayName('Bad\nName'),'Minecraft Console');
});
