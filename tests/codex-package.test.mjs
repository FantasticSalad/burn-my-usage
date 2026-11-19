import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cli = path.join(root, 'scripts/codex-package.mjs');
// macOS tmpdir is under /var, a system symlink the packager's ancestor check refuses.
const tmpRoot = fs.realpathSync(os.tmpdir());
const run = (...args) => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', env: { ...process.env, BURN_MY_USAGE_HOME: path.join(path.dirname(args[1]), 'unused-home'), BMU_BASH: process.env.BMU_BASH || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash') } });

test('fresh allowlisted package detects tampering and refuses overwrite', t => {
  const temp = fs.mkdtempSync(path.join(tmpRoot, "bmu package's "));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const dest = path.join(temp, 'candidate');
  assert.equal(run('prepare', dest).status, 0);
  assert.equal(run('prepare', dest).status, 1);
  assert.equal(run('check', dest).status, 0);
  assert.equal(fs.existsSync(path.join(dest, '.git')), false);
  fs.mkdirSync(path.join(dest, '.git'));
  assert.equal(run('check', dest).status, 1);
  fs.rmdirSync(path.join(dest, '.git'));
  const market = JSON.parse(fs.readFileSync(path.join(dest, '.agents/plugins/marketplace.json'), 'utf8'));
  assert.deepEqual(market.plugins[0].source, { source: 'local', path: './' });
  assert.equal(fs.existsSync(path.join(dest, 'hooks/hooks.json')), false);
  assert.equal(fs.existsSync(path.join(dest, 'plugin.json')), false);
  const portable = JSON.parse(fs.readFileSync(path.join(dest, 'docs/portable-plugin.json'), 'utf8'));
  const overlay = JSON.parse(fs.readFileSync(path.join(dest, '.codex-plugin/plugin.json'), 'utf8'));
  assert.equal(portable.extensions?.['com.openai']?.hooks, './hooks/codex.json');
  assert.equal(overlay.name, portable.name);
  assert.equal(overlay.version, portable.version);
  assert.equal(overlay.description, portable.description);
  assert.equal(overlay.hooks, './hooks/codex.json');
  assert.equal(fs.existsSync(path.join(dest, 'skills/burn-my-usage/scripts/codex-quota-transport.mjs')), true);
  assert.equal(fs.existsSync(path.join(dest, 'skills/burn-my-usage/scripts/usage-validate.awk')), true);
  for (const file of ['README.md', 'SECURITY.md', 'SECURITY_DECISIONS.md', 'docs/DESIGN.md', 'docs/HOST-ARCHITECTURE.md', 'docs/GUARD-REVIEW.md', 'docs/EVAL-ACCOUNTING.md', 'docs/guard-replay.md', 'docs/CODEX-INSTALL.md']) {
    const text = fs.readFileSync(path.join(dest, file), 'utf8');
    for (const match of text.matchAll(/\]\(([^)]+)\)/g)) {
      const target = match[1].split('#')[0];
      if (!target || /^(?:https?:|mailto:)/.test(target)) continue;
      assert.equal(fs.existsSync(path.resolve(dest, path.dirname(file), target)), true, `${file}: ${target}`);
    }
  }
  fs.writeFileSync(path.join(dest, 'unexpected.txt'), 'extra');
  assert.equal(run('check', dest).status, 1);
  fs.unlinkSync(path.join(dest, 'unexpected.txt'));
  const missingBash = spawnSync(process.execPath, [cli, 'check', dest], { encoding: 'utf8', env: { ...process.env, BURN_MY_USAGE_HOME: path.join(temp, 'unused-home'), BMU_BASH: path.join(temp, 'missing-bash') } });
  assert.equal(missingBash.status, 1);
  const configHome = path.join(temp, 'home');
  fs.mkdirSync(configHome);
  const configuredBash = process.env.BMU_BASH || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash');
  fs.writeFileSync(path.join(configHome, 'config.md'), `- codex_bash: \`${configuredBash}\` # comment\n`);
  const configEnv = { ...process.env, BURN_MY_USAGE_HOME: configHome };
  delete configEnv.BMU_BASH;
  assert.equal(spawnSync(process.execPath, [cli, 'check', dest], { encoding: 'utf8', env: configEnv }).status, 0);
  fs.writeFileSync(path.join(configHome, 'config.md'), `- codex_bash: "${configuredBash}" # comment\n`);
  assert.equal(spawnSync(process.execPath, [cli, 'check', dest], { encoding: 'utf8', env: configEnv }).status, 0);
  fs.appendFileSync(path.join(configHome, 'config.md'), `- codex_bash: ${configuredBash}\n`);
  assert.equal(spawnSync(process.execPath, [cli, 'check', dest], { encoding: 'utf8', env: configEnv }).status, 1);
  fs.appendFileSync(path.join(dest, 'LICENSE'), 'changed');
  assert.equal(run('check', dest).status, 1);
});

test('preflight rejects malformed hook selection even if hashes are regenerated', t => {
  const temp = fs.mkdtempSync(path.join(tmpRoot, 'bmu-invalid-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const dest = path.join(temp, 'candidate');
  assert.equal(run('prepare', dest).status, 0);
  const hookFile = path.join(dest, 'hooks/codex.json');
  const hooks = JSON.parse(fs.readFileSync(hookFile, 'utf8'));
  delete hooks.hooks.PreToolUse;
  fs.writeFileSync(hookFile, JSON.stringify(hooks));
  const sumFile = path.join(dest, 'SHA256SUMS.json');
  const sums = JSON.parse(fs.readFileSync(sumFile, 'utf8'));
  sums.find(entry => entry.path === 'hooks/codex.json').sha256 = crypto.createHash('sha256').update(fs.readFileSync(hookFile)).digest('hex');
  fs.writeFileSync(sumFile, JSON.stringify(sums));
  assert.equal(run('check', dest).status, 1);
});

test('preflight rejects mismatched compatibility metadata even with regenerated hashes', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'bmu-overlay-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const dest = path.join(temp, 'candidate');
  assert.equal(run('prepare', dest).status, 0);
  const file = path.join(dest, '.codex-plugin/plugin.json');
  const overlay = JSON.parse(fs.readFileSync(file, 'utf8'));
  overlay.version = '0.0.0';
  fs.writeFileSync(file, JSON.stringify(overlay));
  const sumFile = path.join(dest, 'SHA256SUMS.json');
  const sums = JSON.parse(fs.readFileSync(sumFile, 'utf8'));
  sums.find(entry => entry.path === '.codex-plugin/plugin.json').sha256 = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  fs.writeFileSync(sumFile, JSON.stringify(sums));
  assert.equal(run('check', dest).status, 1);
});

test('preflight refuses an absent or altered Windows supervisor even with new hashes', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'bmu-windows-hook-'));
  t.after(() => fs.rmSync(temp, {recursive:true,force:true}));
  const dest = path.join(temp, 'candidate');
  assert.equal(run('prepare', dest).status, 0);
  const file = path.join(dest, 'hooks/codex.json');
  const original = JSON.parse(fs.readFileSync(file, 'utf8'));
  for (const variant of ['missing', 'altered']) {
    const hooks = structuredClone(original);
    if (variant === 'missing') delete hooks.hooks.PreToolUse[0].hooks[0].commandWindows;
    else hooks.hooks.PreToolUse[0].hooks[0].commandWindows = 'exit 0';
    fs.writeFileSync(file, JSON.stringify(hooks));
    const sumsFile = path.join(dest, 'SHA256SUMS.json');
    const sums = JSON.parse(fs.readFileSync(sumsFile, 'utf8'));
    sums.find(entry => entry.path === 'hooks/codex.json').sha256 = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    fs.writeFileSync(sumsFile, JSON.stringify(sums));
    assert.equal(run('check', dest).status, 1);
  }
});

test('preparation refuses a symlink destination parent', t => {
  const temp = fs.mkdtempSync(path.join(tmpRoot, 'bmu-link-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const real = path.join(temp, 'real');
  const link = path.join(temp, 'link');
  fs.mkdirSync(real);
  try { fs.symlinkSync(real, link, process.platform === 'win32' ? 'junction' : 'dir'); }
  catch (e) { if (e.code === 'EPERM') return t.skip('Creating a symlink is unavailable'); throw e; }
  assert.equal(run('prepare', path.join(link, 'candidate')).status, 1);
  assert.equal(fs.existsSync(path.join(real, 'candidate')), false);
});

test('registered commands preserve paths and stdin in a shell fixture', t => {
  const temp = fs.mkdtempSync(path.join(tmpRoot, "bmu package's "));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const dest = path.join(temp, 'candidate');
  assert.equal(run('prepare', dest).status, 0);
  const hooks = JSON.parse(fs.readFileSync(path.join(dest, 'hooks/codex.json'), 'utf8')).hooks;
  for (const [event, file] of [['SessionStart', 'context-codex.mjs'], ['PreToolUse', 'hook-codex.mjs']]) {
    fs.writeFileSync(path.join(dest, 'skills/burn-my-usage/scripts', file), "process.stdin.pipe(process.stdout);\n");
    const result = spawnSync(hooks[event][0].hooks[0].command, { shell: true, cwd: temp, env: { ...process.env, PLUGIN_ROOT: dest }, input: 'fixture input', encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'fixture input');
  }
  const result = spawnSync(hooks.PreToolUse[0].hooks[0].command, { shell: true, cwd: temp, env: { ...process.env, PLUGIN_ROOT: '' }, encoding: 'utf8' });
  assert.equal(JSON.parse(result.stdout).hookSpecificOutput.permissionDecision, 'deny');
});
