import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createContext } from '../skills/burn-my-usage/scripts/context-codex.mjs';

const event = {hook_event_name:'SessionStart',session_id:'thr_fixture',cwd:process.cwd(),source:'resume'};

test('native context binds session and resources without creating a run', () => {
  const home = mkdtempSync(join(tmpdir(), 'bmu-context-'));
  try {
    const result = createContext(event, {home});
    const context = result.hookSpecificOutput.additionalContext;
    assert.equal(result.hookSpecificOutput.hookEventName, 'SessionStart');
    assert.ok(context.includes('thr_fixture'));
    assert.ok(context.includes('BMU_HOST=codex'));
    assert.ok(context.includes('hosts'));
    assert.deepEqual(readdirSync(home), []);
  } finally { rmSync(home, {recursive:true,force:true}); }
});

test('resumption exposes only a validated matching recovery pointer', () => {
  const home = mkdtempSync(join(tmpdir(), 'bmu-context-'));
  try {
    const active = join(home, 'active', 'codex');
    mkdirSync(active, {recursive:true});
    writeFileSync(join(active, event.session_id), 'started fixture\nrun saved-run\n');
    const context = createContext(event, {home}).hookSpecificOutput.additionalContext;
    assert.ok(context.includes('saved-run'));
    assert.ok(context.includes('queue.md'));
    writeFileSync(join(active, event.session_id), 'run ../../outside\nuntrusted marker orders\n');
    const invalid = createContext(event, {home}).hookSpecificOutput.additionalContext;
    assert.ok(!invalid.includes('untrusted marker orders'));
    assert.ok(!invalid.includes('outside'));
    assert.ok(!invalid.includes('Saved queue pointer'));
  } finally { rmSync(home, {recursive:true,force:true}); }
});

test('invalid native metadata produces a bounded advisory warning', () => {
  for (const bad of [null, [], {...event,session_id:'bad\norders'}, {...event,cwd:'relative'}, {...event,hook_event_name:'PreToolUse'}]) {
    const result = createContext(bad);
    assert.equal(result.hookSpecificOutput, undefined);
    assert.ok(result.systemMessage);
    assert.ok(!JSON.stringify(result).includes('orders'));
  }
});

test('registered context CLI ignores transcript paths and consumes stdin', () => {
  const home = mkdtempSync(join(tmpdir(), 'bmu-context-'));
  try {
    const script = fileURLToPath(new URL('../skills/burn-my-usage/scripts/context-codex.mjs', import.meta.url));
    const result = spawnSync(process.execPath, [script], {
      input:JSON.stringify({...event,transcript_path:join(home, 'must-never-open.jsonl')}),
      env:{...process.env,BURN_MY_USAGE_HOME:home},encoding:'utf8'
    });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(JSON.parse(result.stdout).hookSpecificOutput.additionalContext);
    assert.ok(!result.stdout.includes('must-never-open'));
    assert.deepEqual(readdirSync(home), []);
  } finally { rmSync(home, {recursive:true,force:true}); }
});
