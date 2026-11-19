// Native event shapes, synthetic data only; this does not exercise a native client.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { quotaFixture } from './fixtures/codex-quota-fixture.mjs';

const tmp = mkdtempSync(join(tmpdir(), 'bmu-native-'));
const home = join(tmp, 'home'), code = join(tmp, 'code');
const hook = fileURLToPath(new URL('../skills/burn-my-usage/scripts/hook-codex.mjs', import.meta.url));
try {
  mkdirSync(join(home, 'active', 'codex'), {recursive:true});
  mkdirSync(join(home, 'run.lock')); mkdirSync(join(home, 'usage')); mkdirSync(code);
  writeFileSync(join(home, 'run.lock', 'owner'), 'codex\ns1\ns1\n');
  writeFileSync(join(home, 'active', 'codex', 's1'), 'active');
  writeFileSync(join(home, 'roots.txt'), code + '\n');
  const now = Math.floor(Date.now()/1000);
  writeFileSync(join(home, 'usage', 'codex.json'), JSON.stringify({provider:'codex',source:'app-server-account-rate-limits',capturedAt:now,windows:[{usedPercent:10,windowDurationMins:10080,resetsAt:now+86400}]}));
  const env = quotaFixture(tmp, {...process.env,BURN_MY_USAGE_HOME:home,...(process.platform === 'win32' ? {BMU_BASH:process.env.BMU_BASH || join(process.env.ProgramFiles, 'Git', 'bin', 'bash.exe')} : {})});
  const base = {session_id:'s1',cwd:code,hook_event_name:'PreToolUse',tool_name:'Bash',tool_input:{command:'echo ok'}};
  function run(event, raw = false) {
    const r = spawnSync(process.execPath,[hook],{input:raw ? event : JSON.stringify(event),encoding:'utf8',env});
    assert.equal(r.status,0,r.stderr);
    return r.stdout.trim() ? JSON.parse(r.stdout).hookSpecificOutput.permissionDecision : 'no-decision';
  }
  const call = (tool_name, tool_input, extra={}) => run({...base,tool_name,tool_input,...extra});
  assert.equal(run(base),'no-decision');
  assert.equal(run({...base,agent_id:'child-1',agent_type:'worker'}),'no-decision');
  assert.equal(run({...base,session_id:'another'}),'no-decision');
  assert.equal(run({...base,session_id:'../bad'}),'deny');
  assert.equal(run('{bad',true),'deny');
  assert.equal(call('Bash',{command:'cat ~/.codex/auth.json'}),'deny');
  assert.equal(call('Bash',{command:'rm ./config.md',workdir:home}),'deny');
  assert.equal(call('Bash',{command:'echo ok',cwd:code,workdir:home}),'deny');
  assert.equal(call('Bash',{command:'echo ok',shell:'powershell'}),'deny');
  assert.equal(call('functions.exec_command',{cmd:'rm ./config.md',cwd:home}),'deny');
  assert.equal(call('functions.exec_command',{cmd:'echo ok',shell:'powershell'}),'deny');
  assert.equal(call('functions.apply_patch',{patch:'*** Begin Patch\n*** Add File: a\n+x\n*** End Patch\n',cwd:home}),'deny');
  assert.equal(call('Bash',{command:4}),'deny');
  assert.equal(call('functions.write_stdin',{chars:'x'}),'deny');
  assert.equal(call('mcp__service__sync_state',{}),'deny');
  const patch = '*** Begin Patch\n*** Add File: good.txt\n+ok\n*** Add File: .codex/config.toml\n+bad\n*** End Patch\n';
  assert.equal(call('apply_patch',{command:patch}),'deny');
  assert.equal(call('apply_patch',{command:'*** Begin Patch\n*** Add File: a.txt\n+ok\n*** End Patch\n'}),'no-decision');
  assert.equal(call('apply_patch',{command:patch,workdir:home}),'deny');
  assert.equal(call('apply_patch',{command:5}),'deny');
  if (process.platform === 'win32') {
    writeFileSync(join(home,'config.md'), `- codex_bash: \`${env.BMU_BASH}\` # installed Git Bash\n`);
    const configEnv = {...env}; delete configEnv.BMU_BASH;
    const r = spawnSync(process.execPath,[hook],{input:JSON.stringify(base),encoding:'utf8',env:configEnv});
    assert.equal(r.status,0,r.stderr); assert.equal(r.stdout.trim(),'');
  }
  writeFileSync(join(home,'run.lock','owner'), 'cod\ns1\n');
  assert.equal(run(base),'deny');
  writeFileSync(join(home,'run.lock','owner'), '');
  assert.equal(run(base),'deny');
  writeFileSync(join(home,'run.lock','owner'), 'claude-code\ns2\n');
  assert.equal(run({...base,session_id:'other'}),'no-decision');
  rmSync(join(home,'run.lock'),{recursive:true});
  assert.equal(run(base),'deny');
  assert.equal(run('{bad',true),'no-decision');
  console.log('codex-hooks: synthetic native envelopes passed');
} finally { rmSync(tmp,{recursive:true,force:true}); }
