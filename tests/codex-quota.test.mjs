import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { collectQuota } from '../skills/burn-my-usage/scripts/codex-quota-transport.mjs';
import { quotaFixture } from './fixtures/codex-quota-fixture.mjs';
import { existsSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const bucket = { limitId: 'codex', primary: { usedPercent: 3, windowDurationMins: 10080, resetsAt: 2000000000 } };
function fixture(onRequest) {
  const child = new EventEmitter();
  child.stdin = new PassThrough(); child.stdout = new PassThrough(); child.stderr = new PassThrough();
  child.kill = () => { child.killed = true; process.nextTick(() => child.emit('close', null)); return true; };
  let input = '';
  child.stdin.on('data', chunk => {
    input += chunk;
    let i;
    while ((i = input.indexOf('\n')) >= 0) {
      const message = JSON.parse(input.slice(0, i)); input = input.slice(i + 1);
      onRequest(message, child);
    }
  });
  return child;
}
const reply = (child, message) => child.stdout.write(JSON.stringify(message) + '\n');

test('fixed handshake tolerates interleaved notifications and selects codex bucket', async () => {
  const methods = [];
  const child = fixture((m, c) => {
    methods.push(m.method);
    if (m.id === 1) { reply(c, { method: 'notice', params: { discarded: 'discard' } }); reply(c, { id: 1, result: {} }); }
    if (m.id === 2) reply(c, { id: 2, result: { rateLimits: { limitId: 'other' }, rateLimitsByLimitId: { codex: bucket } } });
  });
  assert.deepEqual(await collectQuota({ spawnChild: () => child }), { result: { rateLimits: bucket } });
  assert.deepEqual(methods, ['initialize', 'initialized', 'account/rateLimits/read']);
  assert.equal(child.killed, true);
});

test('fails when the client cannot be stopped or does not close', async () => {
  for (const kill of [() => false, () => true]) {
    const child = fixture((m, c) => {
      if (m.id === 1) reply(c, { id: 1, result: {} });
      if (m.id === 2) reply(c, { id: 2, result: { rateLimits: bucket } });
    });
    child.kill = kill;
    await assert.rejects(collectQuota({ spawnChild: () => child }));
  }
});

test('rejects errors, unsupported buckets and unexpected requests without exposing content', async () => {
  for (const payload of [
    { id: 2, error: { message: 'synthetic-secret' } },
    { id: 2, result: { rateLimitsByLimitId: { other: bucket } } },
    { id: 9, method: 'server/request', params: { discarded: 'synthetic-secret' } },
    { id: 2, result: { rateLimits: { limitId: 'other' } } },
  ]) {
    const child = fixture((m, c) => {
      if (m.id === 1) reply(c, { id: 1, result: {} });
      if (m.id === 2) reply(c, payload);
    });
    await assert.rejects(collectQuota({ spawnChild: () => child }), { message: 'Codex quota collection failed' });
    assert.equal(child.killed, true);
  }
});

test('rejects malformed output, excess output, process failure and timeout', async () => {
  for (const kind of ['malformed', 'oversize', 'close', 'timeout']) {
    const child = fixture((m, c) => {
      if (m.id !== 1) return;
      if (kind === 'malformed') c.stdout.write('{bad\n');
      if (kind === 'oversize') c.stderr.write('x'.repeat(100));
      if (kind === 'close') process.nextTick(() => c.emit('close', 1));
    });
    await assert.rejects(collectQuota({ spawnChild: () => child, timeoutMs: 20, maxBytes: 50 }));
    if (kind !== 'close') assert.equal(child.killed, true);
  }
});

test('live check uses fresh quota and fails closed on missing windows or storage failure', () => {
  const dir = mkdtempSync(join(tmpdir(), 'bmu-quota-'));
  try {
    const home = join(dir, 'home'), mode = join(dir, 'mode'); mkdirSync(home);
    const env = quotaFixture(dir, { ...process.env, BURN_MY_USAGE_HOME: home, BMU_TEST_QUOTA_MODE_FILE: mode });
    const script = fileURLToPath(new URL('../skills/burn-my-usage/scripts/usage-codex.mjs', import.meta.url));
    const check = () => { const r = spawnSync(process.execPath, [script, 'check'], { env, encoding: 'utf8', timeout: 25000 }); assert.equal(r.status, 0, r.stderr); return r.stdout; };
    writeFileSync(mode, 'go'); assert.match(check(), /verdict=go/);
    const relative = spawnSync(process.execPath, [script, 'check'], { env: { ...env, BMU_CODEX_BIN: 'relative-codex' }, encoding: 'utf8' });
    assert.match(relative.stdout, /verdict=unknown/);
    env.BMU_CODEX_BIN = join(dir, 'quota-bin', process.platform === 'win32' ? 'codex.exe' : 'codex');
    assert.match(check(), /verdict=go/);
    writeFileSync(mode, 'reached'); assert.match(check(), /verdict=stop/);
    const reached = spawnSync(process.execPath, [script, 'read'], { env, encoding: 'utf8' });
    assert.match(reached.stdout, /verdict=stop/);
    assert.match(reached.stdout, /Codex reports a reached quota limit/);
    writeFileSync(mode, 'go'); assert.match(check(), /verdict=go/);
    writeFileSync(mode, 'error-unlink-fail'); assert.match(check(), /verdict=unknown/);
    assert.equal(existsSync(join(home, 'usage', 'codex.json')), true);
    writeFileSync(mode, 'missing'); assert.match(check(), /verdict=unknown/);
    writeFileSync(mode, 'go');
    mkdirSync(join(home, 'usage', 'codex.json'));
    assert.match(check(), /verdict=unknown/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
