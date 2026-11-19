#!/usr/bin/env node
// Prepare a review copy, or check its bytes and local dependencies. No installation.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { windowsHookCommand } from './codex-windows-hook.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const files = [
  'docs/portable-plugin.json', '.codex-plugin/plugin.json', 'hooks/codex.json', 'LICENSE', 'README.md', 'SECURITY.md', 'SECURITY_DECISIONS.md',
  'docs/HOST-ARCHITECTURE.md', 'docs/CODEX-INSTALL.md', 'docs/NATIVE-ACCEPTANCE.md', 'docs/DESIGN.md', 'docs/GUARD-REVIEW.md',
  'docs/EVAL-ACCOUNTING.md', 'docs/guard-replay.md', 'scripts/codex-package.mjs', 'scripts/codex-native-check.mjs', 'scripts/codex-windows-hook.mjs',
  ...['SKILL.md', 'inbox.md', 'lessons.md', 'recurring.md', 'setup.md', 'workflow.md', 'worktrees.md',
    'hosts/claude-code.md', 'hosts/codex.md',
    'scripts/context-codex.mjs', 'scripts/hook-codex.mjs', 'scripts/hook-supervisor.ps1', 'scripts/guard-codex.mjs', 'scripts/guard.sh',
    'scripts/leak-check.sh', 'scripts/lib.sh', 'scripts/repo-check.sh', 'scripts/start.sh', 'scripts/stop.sh',
    'scripts/usage-codex.mjs', 'scripts/codex-quota-transport.mjs', 'scripts/usage-tap.sh', 'scripts/usage-validate.awk', 'scripts/usage.sh', 'scripts/work-item.sh',
    'templates/config.md', 'templates/INBOX.md', 'templates/lessons.md', 'templates/log.md', 'templates/wishlist.md']
    .map(f => `skills/burn-my-usage/${f}`)
].sort();
const manifestName = 'SHA256SUMS.json';
// Preserve portable identity as documentation; these clients ignore bundled hooks
// whenever a schema-bearing portable manifest is at the installed package root.
const sourceNames = { 'docs/portable-plugin.json': 'plugin.json' };
const marketplaceName = '.agents/plugins/marketplace.json';
const marketplace = JSON.stringify({
  name: 'burn-my-usage-local',
  interface: { displayName: 'Burn My Usage Local' },
  plugins: [{ name: 'burn-my-usage', source: { source: 'local', path: './' }, policy: { installation: 'AVAILABLE', authentication: 'ON_INSTALL' }, category: 'Productivity' }]
}, null, 2) + '\n';
const digest = b => crypto.createHash('sha256').update(b).digest('hex');
function fail(s) { throw new Error(s); }
function regular(base, name) {
  let current = base;
  for (const part of name.split('/')) {
    current = path.join(current, part);
    const st = fs.lstatSync(current);
    if (st.isSymbolicLink()) fail(`Symlink refused: ${name}`);
  }
  if (!fs.statSync(current).isFile()) fail(`Not a regular file: ${name}`);
  return current;
}
function entries(base, source = false) {
  return files.map(name => ({ path: name, sha256: digest(fs.readFileSync(regular(base, source ? sourceNames[name] || name : name))) }));
}
function noSymlinkAncestors(target) {
  let p = path.parse(target).root;
  for (const part of target.slice(p.length).split(path.sep).filter(Boolean)) {
    p = path.join(p, part);
    if (fs.lstatSync(p).isSymbolicLink()) fail('Destination path contains a symlink');
  }
}
function prepare(destination) {
  if (!path.isAbsolute(destination)) fail('Destination must be an absolute path');
  const dest = path.resolve(destination);
  if (dest === path.parse(dest).root || dest === root || dest.startsWith(root + path.sep) || root.startsWith(dest + path.sep)) fail('Destination must be outside the source tree');
  const parent = path.dirname(dest);
  noSymlinkAncestors(parent);
  if (!fs.statSync(parent).isDirectory()) fail('Destination parent must exist');
  const manifest = [...entries(root, true), { path: marketplaceName, sha256: digest(marketplace) }].sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0); // Check all sources first.
  fs.mkdirSync(dest); // Fails if anything already exists at the destination.
  for (const entry of manifest) {
    const out = path.join(dest, ...entry.path.split('/'));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    if (entry.path === marketplaceName) fs.writeFileSync(out, marketplace, { flag: 'wx' });
    else fs.copyFileSync(regular(root, sourceNames[entry.path] || entry.path), out, fs.constants.COPYFILE_EXCL);
    if (digest(fs.readFileSync(out)) !== entry.sha256) fail(`Source changed during copy: ${entry.path}`);
  }
  fs.writeFileSync(path.join(dest, manifestName), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
  console.log(`Prepared ${manifest.length} files in ${dest}. Review is required; this is not a release approval.`);
}
function inventory(base, prefix = '') {
  return fs.readdirSync(path.join(base, prefix), { withFileTypes: true }).flatMap(e => {
    const name = prefix ? `${prefix}/${e.name}` : e.name;
    if (e.isSymbolicLink()) fail(`Symlink refused: ${name}`);
    if (e.isDirectory()) return [`${name}/`, ...inventory(base, name)];
    if (!e.isFile()) fail(`Non-file refused: ${name}`);
    return [name];
  });
}
function check(base) {
  noSymlinkAncestors(base);
  const expected = JSON.parse(fs.readFileSync(regular(base, manifestName), 'utf8'));
  const actual = [...entries(base), { path: marketplaceName, sha256: digest(fs.readFileSync(regular(base, marketplaceName))) }].sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  if (JSON.stringify(expected) !== JSON.stringify(actual)) fail('Inventory or hashes do not match');
  if (fs.readFileSync(regular(base, marketplaceName), 'utf8') !== marketplace) fail('Marketplace descriptor is invalid');
  const allowedFiles = [...files, manifestName, marketplaceName];
  const allowedDirs = new Set();
  for (const file of allowedFiles) {
    const parts = file.split('/');
    parts.pop();
    while (parts.length) { allowedDirs.add(`${parts.join('/')}/`); parts.pop(); }
  }
  if (JSON.stringify(inventory(base).sort()) !== JSON.stringify([...allowedFiles, ...allowedDirs].sort())) fail('Unexpected package files or directories');
  const manifest = JSON.parse(fs.readFileSync(regular(base, 'docs/portable-plugin.json'), 'utf8'));
  const overlay = JSON.parse(fs.readFileSync(regular(base, '.codex-plugin/plugin.json'), 'utf8'));
  if (manifest.$schema !== 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json' || manifest.name !== 'burn-my-usage' || manifest.extensions?.['com.openai']?.hooks !== './hooks/codex.json' ||
      overlay.name !== manifest.name || overlay.version !== manifest.version || overlay.description !== manifest.description || overlay.hooks !== './hooks/codex.json') fail('Codex manifest is invalid');
  const hooks = JSON.parse(fs.readFileSync(regular(base, 'hooks/codex.json'), 'utf8')).hooks;
  for (const [event, script] of [['SessionStart', 'context-codex.mjs'], ['PreToolUse', 'hook-codex.mjs']]) {
    const group = hooks?.[event];
    const hook = group?.[0]?.hooks?.[0];
    if (!Array.isArray(group) || group.length !== 1 || group[0].hooks.length !== 1 || hook.type !== 'command' || typeof hook.command !== 'string' || !hook.command.includes(`skills/burn-my-usage/scripts/${script}`) || !hook.command.includes('process.env.PLUGIN_ROOT')) fail(`Invalid ${event} hook`);
  }
  if (Object.keys(hooks).sort().join(',') !== 'PreToolUse,SessionStart') fail('Unexpected hook event');
  const windowsGuard = hooks.PreToolUse[0].hooks[0];
  const windowsSource = fs.readFileSync(regular(base, 'skills/burn-my-usage/scripts/hook-supervisor.ps1'), 'utf8');
  if (windowsGuard.timeout !== 40 || windowsGuard.commandWindows !== windowsHookCommand(windowsSource)) fail('Invalid Windows supervisor selection');
  if (Number(process.versions.node.split('.')[0]) < 18) fail('Node 18 or later is required');
  const home = process.env.BURN_MY_USAGE_HOME || path.join(process.env.HOME || os.homedir(), '.burn-my-usage');
  let config = '';
  try { config = fs.readFileSync(path.join(home, 'config.md'), 'utf8'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const matches = [...config.matchAll(/^[\t ]*[-*]?[\t ]*codex_bash[\t ]*:[\t ]*(.*)$/gmi)];
  if (!process.env.BMU_BASH && matches.length > 1) fail('Duplicate codex_bash config keys');
  const configured = (matches[0]?.[1] || '').replace(/[\t ]+#.*$/, '').trim().replace(/^(['"`])(.*)\1$/, '$2');
  const bash = process.env.BMU_BASH || configured || (process.platform === 'win32' ? '' : 'bash');
  if (!bash || (process.platform === 'win32' && !path.isAbsolute(bash))) fail('Set BMU_BASH or codex_bash to the absolute Git Bash executable path');
  for (const [program, args] of [[bash, ['--version']], ['git', ['--version']]]) {
    const result = spawnSync(program, args, { stdio: 'ignore' });
    if (result.error || result.status !== 0) fail(`Required executable unavailable: ${program === bash ? 'bash' : 'git'}`);
  }
  console.log('Package bytes, inventory, Node, Bash and Git checked. Native installation, hook enforcement and usage acceptance remain unverified.');
}
try {
  const [action, arg, ...extra] = process.argv.slice(2);
  if (extra.length || !arg || !['prepare', 'check'].includes(action)) fail('Usage: node scripts/codex-package.mjs prepare|check ABSOLUTE_PATH');
  if (!path.isAbsolute(arg)) fail('Path must be absolute');
  if (action === 'prepare') prepare(arg); else check(path.resolve(arg));
} catch (e) { console.error(`Package error: ${e.message}`); process.exitCode = 1; }
