// Synthetic offline adapter fixtures; no native hooks or model calls.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { quotaFixture } from './fixtures/codex-quota-fixture.mjs';

const tmp = mkdtempSync(join(tmpdir(), 'bmu-host-'));
const home = join(tmp, 'home'), code = join(tmp, 'code');
const adapter = fileURLToPath(new URL('../skills/burn-my-usage/scripts/guard-codex.mjs', import.meta.url));
try {
  mkdirSync(join(home, 'active', 'codex'), {recursive:true}); mkdirSync(code);
  writeFileSync(join(home, 'active', 'codex', 's1'), 'active');
  writeFileSync(join(home, 'roots.txt'), code + '\n');
  const now = Math.floor(Date.now()/1000);
  mkdirSync(join(home, 'usage'));
  function usage(t) { writeFileSync(join(home, 'usage', 'codex.json'), JSON.stringify({provider:'codex',source:'app-server-account-rate-limits',capturedAt:t,windows:[{usedPercent:10,windowDurationMins:10080,resetsAt:now+86400}]})); }
  usage(now);
  const mode = join(tmp, 'mode'); writeFileSync(mode, 'go');
  const env = quotaFixture(tmp, {...process.env,BURN_MY_USAGE_HOME:home,BMU_HOST:'codex',BMU_SESSION_ID:'s1', BMU_TEST_QUOTA_MODE_FILE:mode,
    ...(process.platform === 'win32' ? {BMU_BASH:process.env.BMU_BASH || join(process.env.ProgramFiles, 'Git', 'bin', 'bash.exe')} : {})});
  function invoke(tool, input, overrides={}) {
    const r = spawnSync(process.execPath, [adapter], {input:JSON.stringify({session_id:'s1',cwd:code,tool_name:tool,tool_input:input,...overrides}),encoding:'utf8',env});
    assert.equal(r.status, 0, r.stderr);
    return r.stdout.trim() ? JSON.parse(r.stdout).hookSpecificOutput.permissionDecision : 'no-decision';
  }
  const add = p => `*** Begin Patch\n*** Add File: ${p}\n+hello\n*** End Patch\n`;
  assert.equal(invoke('functions.apply_patch', {patch:add('a.txt')}), 'no-decision');
  assert.equal(invoke('functions.apply_patch', {patch:'*** Begin Patch\n*** Add File: a.txt\n+hello\n*** Add File: .codex/config.toml\n+bad\n*** End Patch\n'}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:'*** Begin Patch\n*** Update File: a.txt\n*** Move to: .agents/settings\n@@\n-old\n+new\n*** End Patch\n'}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:add('../outside')}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:add('.claude/settings.json')}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:add('.codex/auth.json')}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:add(join(home, 'INBOX.md')).replace('+hello','+- [x] Merge')}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:`*** Begin Patch\n*** Update File: a.txt\n*** Move to: ${join(home, 'INBOX.md')}\n@@\n-old\n+new\n*** End Patch\n`}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:`*** Begin Patch\n*** Update File: ${join(home, 'INBOX.md')}\n*** Move to: a.txt\n@@\n-old\n+new\n*** End Patch\n`}), 'deny');
  const dotInbox = `${home}/./INBOX.md`;
  assert.equal(invoke('functions.apply_patch', {patch:`*** Begin Patch\n*** Delete File: ${join(home, 'INBOX.md')}\n*** End Patch\n`}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:`*** Begin Patch\n*** Delete File: ${dotInbox}\n*** End Patch\n`}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:add(dotInbox).replace('+hello','+- [x] Merge')}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:`*** Begin Patch\n*** Update File: a.txt\n*** Move to: ${dotInbox}\n@@\n-old\n+new\n*** End Patch\n`}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:`*** Begin Patch\n*** Update File: ${dotInbox}\n*** Move to: a.txt\n@@\n-old\n+new\n*** End Patch\n`}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:'*** Begin Patch\n*** Unknown File: a\n*** End Patch\n'}), 'deny');
  assert.equal(invoke('functions.write_stdin', {session_id:1,chars:'git push'}), 'deny');
  assert.equal(invoke('mcp__service__sync_state', {}), 'deny');
  assert.equal(invoke('functions.exec_command', {cmd:'echo ok'}), 'no-decision');
  assert.equal(invoke('functions.exec_command', {cmd:'cat ~/.codex/auth.json'}), 'deny');
  assert.equal(invoke('functions.exec_command', {cmd:'git push --force origin main'}), 'deny');
  for (const p of ['owned/codex/s1/app-item', 'run.lock/owner', 'usage/codex.json', 'usage.json', 'config.md']) {
    assert.equal(invoke('functions.exec_command', {cmd:`rm "${home}/${p}"`}), 'deny', p);
    assert.equal(invoke('functions.exec_command', {cmd:`cp source "${home}/./${p}"`}), 'deny', p);
    assert.equal(invoke('functions.exec_command', {cmd:`echo bad > "${home}/${p}"`}), 'deny', p);
  }
  assert.equal(invoke('functions.exec_command', {cmd:'cp source config.md'}), 'no-decision');
  assert.equal(invoke('functions.exec_command', {cmd:'rm ./config.md',workdir:home}), 'deny');
  assert.equal(invoke('functions.exec_command', {cmd:`rmdir "${home}/run.lock"`}), 'deny');
  assert.equal(invoke('functions.apply_patch', {patch:add('a.txt')}, {session_id:'other'}), 'deny');
  writeFileSync(mode, 'error');
  assert.equal(invoke('functions.apply_patch', {patch:add('a.txt')}), 'deny');
  console.log('guard-host: 40 synthetic checks passed');
} finally { rmSync(tmp, {recursive:true,force:true}); }
