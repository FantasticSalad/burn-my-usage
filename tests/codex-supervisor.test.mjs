// Offline synthetic checks for the Windows supervisor; no native client is started.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { windowsHookCommand } from '../scripts/codex-windows-hook.mjs';

const supervisor = fileURLToPath(new URL('../skills/burn-my-usage/scripts/hook-supervisor.ps1', import.meta.url));
const powershell = join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
const skip = process.platform !== 'win32';
const command = windowsHookCommand(readFileSync(supervisor, 'utf8'));

test('registered Windows command matches generated template', () => {
  const hooks = JSON.parse(readFileSync(new URL('../hooks/codex.json', import.meta.url), 'utf8'));
  assert.equal(hooks.hooks.PreToolUse[0].hooks[0].commandWindows, command);
});

test('Windows supervisor refuses failed or invalid Node responses', {skip, timeout:60000}, t => {
  const root = mkdtempSync(join(tmpdir(), "bmu supervisor's "));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  const bridgeDir = join(root, 'skills', 'burn-my-usage', 'scripts');
  mkdirSync(bridgeDir, {recursive:true});
  const bridge = join(bridgeDir, 'hook-codex.mjs');
  const env = {...process.env, PATH:dirname(process.execPath), PLUGIN_ROOT:root};
  delete env.NODE_OPTIONS;
  const run = (extra={}, input='{}') => {
    const result = spawnSync(powershell, ['-NoLogo','-NoProfile','-NonInteractive','-Command',command], {
      input, encoding:'utf8', env:{...env,...extra}, timeout:25000, windowsHide:true,
    });
    assert.equal(result.status, 0, `supervisor exit ${result.status}: ${result.stderr}`);
    assert.equal(result.stderr, '');
    const output = result.stdout.trim();
    if (!output) return 'allow';
    const denial = JSON.parse(output);
    assert.equal(denial.hookSpecificOutput?.hookEventName, 'PreToolUse');
    assert.equal(denial.hookSpecificOutput?.permissionDecision, 'deny');
    return 'deny';
  };
  const expectDeny = () => assert.equal(run(), 'deny');
  writeFileSync(bridge, "process.stdin.resume(); process.stdin.on('end', () => console.log('BMU_CODEX_ALLOW_V1'));\n");
  assert.equal(run(), 'allow');
  assert.equal(run({PATH:root}), 'deny');
  assert.equal(run({PLUGIN_ROOT:''}), 'deny');
  assert.equal(run({PLUGIN_ROOT:join(root, 'missing')}), 'deny');
  assert.equal(run({}, 'x'.repeat(262145)), 'deny');
  const crash = join(root, 'crash.cjs');
  writeFileSync(crash, "throw Error('synthetic preload failure');\n");
  assert.equal(run({NODE_OPTIONS:`--require=${JSON.stringify(crash)}`}), 'deny');
  for (const source of [
    '',
    "console.log('BMU_CODEX_ALLOW_V1'); console.log('extra');",
    "console.log('BMU_CODEX_ALLOW_V1'); process.exitCode=1;",
    "console.log('BMU_CODEX_DENY_V1');",
    "process.stdout.write('x'.repeat(5000));",
  ]) {
    writeFileSync(bridge, source);
    expectDeny();
  }
  writeFileSync(bridge, 'setInterval(() => {}, 1000);');
  expectDeny();
});

test('Windows supervisor accepts inactive and refuses inconsistent synthetic state', {skip, timeout:15000}, t => {
  const root = mkdtempSync(join(tmpdir(), "bmu state's "));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  const home = join(root, 'home');
  mkdirSync(home);
  const event = JSON.stringify({session_id:'s1',cwd:root,hook_event_name:'PreToolUse',tool_name:'Bash',tool_input:{command:'echo ok'}});
  const pluginRoot = fileURLToPath(new URL('..', import.meta.url));
  const env = {...process.env, PATH:dirname(process.execPath), BURN_MY_USAGE_HOME:home, PLUGIN_ROOT:pluginRoot};
  delete env.NODE_OPTIONS;
  const run = () => spawnSync(powershell, ['-NoLogo','-NoProfile','-NonInteractive','-Command',command], {
    input:event, encoding:'utf8', env, timeout:12000, windowsHide:true,
  });
  let result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), '');
  mkdirSync(join(home, 'active', 'codex'), {recursive:true});
  writeFileSync(join(home, 'active', 'codex', 's1'), 'active');
  result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).hookSpecificOutput.permissionDecision, 'deny');
});
