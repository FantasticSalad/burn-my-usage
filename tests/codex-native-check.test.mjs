import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assessNative } from '../scripts/codex-native-check.mjs';

test('missing, untrusted, disabled or conflicting hooks block native acceptance', () => {
  const pluginId = 'burn-my-usage@burn-my-usage-local';
  const skills = {data:[{skills:[{name:'burn-my-usage:burn-my-usage',enabled:true}],errors:[]}]};
  const trusted = ['sessionStart','preToolUse'].map(eventName => ({pluginId,eventName,enabled:true,trustStatus:'trusted'}));
  const check = hooks => assessNative({data:[{hooks,errors:[]}]}, skills, pluginId);
  assert.equal(check([]).status, 'blocked');
  assert.equal(check(trusted.map(h => ({...h,trustStatus:'untrusted'}))).status, 'blocked');
  assert.equal(check(trusted.map(h => ({...h,enabled:false}))).status, 'blocked');
  assert.equal(check([...trusted,{...trusted[0],trustStatus:'modified'}]).status, 'blocked');
  const ready = check(trusted);
  assert.equal(ready.status, 'ready-for-enforcement-tests');
  assert.equal(ready.enforcementAccepted, false);
  assert.equal(assessNative({data:[{hooks:trusted,errors:[]}]},{data:[]},pluginId).status,'blocked');
});
