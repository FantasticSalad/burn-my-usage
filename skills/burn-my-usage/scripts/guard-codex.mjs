#!/usr/bin/env node
// Experimental offline adapter, Node 18+. This is not a registered runtime hook.
// Input: {session_id, cwd, tool_name, tool_input}. No output means no decision;
// a denial uses the existing guard's JSON shape. Native integration is unverified.
import { readFileSync, existsSync, appendFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve, isAbsolute, win32 } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const session = process.env.BMU_SESSION_ID || '';
const home = process.env.BURN_MY_USAGE_HOME || resolve(process.env.HOME || homedir(), '.burn-my-usage');
const active = process.env.BMU_HOST === 'codex' && /^[A-Za-z0-9_-]+$/.test(session) &&
  existsSync(resolve(home, 'active', 'codex', session));
if (!active) process.exit(0);
function deny(reason) {
  try { appendFileSync(resolve(home, 'guard.log'), `${new Date().toISOString()}\t${session}\tcodex-adapter\t${reason}\n`); } catch {}
  console.log(JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',permissionDecision:'deny',permissionDecisionReason:`burn-my-usage guard: ${reason}`}}));
  process.exit(0);
}
let event;
try { event = JSON.parse(readFileSync(0, 'utf8')); } catch { deny('malformed tool input'); }
if (!event || Array.isArray(event) || event.session_id !== session || typeof event.cwd !== 'string' ||
    !(isAbsolute(event.cwd) || win32.isAbsolute(event.cwd)) || typeof event.tool_name !== 'string' ||
    !event.tool_input || typeof event.tool_input !== 'object' || Array.isArray(event.tool_input)) deny('invalid tool envelope');
const {cwd, tool_input: args} = event;
const guard = resolve(dirname(fileURLToPath(import.meta.url)), 'guard.sh');
// Windows callers must supply the absolute path to their installed Git Bash.
// This avoids accidentally launching WSL's bash through PATH.
const bash = process.env.BMU_BASH || (process.platform === 'win32' ? '' : 'bash');
if (!bash || (process.platform === 'win32' && !win32.isAbsolute(bash))) deny('BMU_BASH must name the installed Git Bash by absolute path');
function check(tool, input) {
  const result = spawnSync(bash, [guard], {input:JSON.stringify({session_id:session,cwd,tool_name:tool,tool_input:input}), encoding:'utf8', env:process.env});
  if (result.error || result.status !== 0) deny('common guard failed');
  if (result.stdout.trim()) {
    try { if (JSON.parse(result.stdout).hookSpecificOutput.permissionDecision !== 'deny') throw Error(); }
    catch { deny('invalid common guard response'); }
    process.stdout.write(result.stdout); process.exit(0);
  }
}
function absolute(p) {
  if (typeof p !== 'string' || !p || /[\x00-\x1f]/.test(p)) deny('invalid patch path');
  // Keep traversal visible to the common guard instead of normalizing it away.
  return isAbsolute(p) || win32.isAbsolute(p) ? p : `${cwd.replace(/[\\/]$/, '')}/${p}`;
}
function lexical(p) { return p.replace(/\\/g, '/').replace(/\/\.(?=\/|$)/g, '').replace(/\/+/g, '/').replace(/\/$/, '').toLowerCase(); }
function isInbox(p) { return lexical(absolute(p)) === lexical(`${home}/inbox.md`); }
function checkPath(p, added = '') {
  p = absolute(p);
  if (isInbox(p) && /\[[xX]\]/.test(added)) deny('patch adds a ticked inbox box');
  check('Edit', {file_path:p, old_string:'', new_string:added});
}
function patch(text) {
  if (typeof text !== 'string' || text.includes('\r')) deny('invalid patch');
  const lines = text.split('\n');
  if (lines.pop() === '') {} else deny('patch must end with a newline');
  if (lines.shift() !== '*** Begin Patch' || lines.pop() !== '*** End Patch' || !lines.length) deny('invalid patch boundaries');
  let i = 0;
  while (i < lines.length) {
    const header = /^\*\*\* (Add|Update|Delete) File: (.+)$/.exec(lines[i++] || '');
    if (!header) deny('unsupported patch operation');
    const [, op, path] = header;
    let moved = null, added = '', body = 0, hunk = false;
    if (op === 'Update' && (lines[i] || '').startsWith('*** Move to: ')) moved = lines[i++].slice(13);
    while (i < lines.length && !/^\*\*\* (Add|Update|Delete) File: /.test(lines[i])) {
      const line = lines[i++];
      if (op === 'Delete') deny('invalid delete patch');
      if (op === 'Add') { if (!line.startsWith('+')) deny('invalid add patch'); added += line.slice(1) + '\n'; body++; continue; }
      if (line === '*** End of File') { if (!hunk) deny('invalid end of file marker'); continue; }
      if (line === '@@' || line.startsWith('@@ ')) { hunk = true; continue; }
      if (!hunk || !/^[ +\-]/.test(line)) deny('invalid update patch');
      if (line.startsWith('+')) added += line.slice(1) + '\n';
      body++;
    }
    if (op !== 'Delete' && !body) deny('empty patch operation');
    if (op === 'Delete' && isInbox(path)) deny('deleting the inbox is refused');
    if (moved !== null && (isInbox(path) || isInbox(moved))) deny('moving the inbox is refused');
    checkPath(path, added);
    if (moved !== null) checkPath(moved, added);
  }
}
const tool = event.tool_name;
if (tool === 'functions.exec_command' || tool === 'exec_command') {
  if (typeof args.cmd !== 'string' || !args.cmd || args.shell !== undefined || args.env !== undefined ||
      (args.cwd !== undefined && args.workdir !== undefined && args.cwd !== args.workdir)) deny('invalid command input');
  const requestedCwd = args.workdir ?? args.cwd;
  if (requestedCwd !== undefined && (typeof requestedCwd !== 'string' || !(isAbsolute(requestedCwd) || win32.isAbsolute(requestedCwd)))) deny('invalid command directory');
  // Use the actual command workdir, not the envelope's default.
  const commandCwd = requestedCwd || cwd;
  const result = spawnSync(bash, [guard], {input:JSON.stringify({session_id:session,cwd:commandCwd,tool_name:'Bash',tool_input:{command:args.cmd}}), encoding:'utf8', env:process.env});
  if (result.error || result.status !== 0) deny('common guard failed');
  if (result.stdout.trim()) { try { if (JSON.parse(result.stdout).hookSpecificOutput.permissionDecision !== 'deny') throw Error(); } catch { deny('invalid common guard response'); } process.stdout.write(result.stdout); }
} else if (tool === 'functions.apply_patch' || tool === 'apply_patch') {
  if (args.cwd !== undefined || args.workdir !== undefined) deny('unsupported patch directory override');
  patch(typeof args.patch === 'string' ? args.patch : args.input);
} else {
  deny('unsupported tool or persistent session input');
}
