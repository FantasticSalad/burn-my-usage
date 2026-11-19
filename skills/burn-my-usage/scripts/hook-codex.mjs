#!/usr/bin/env node
// Native PreToolUse bridge. No native session files or transcript paths are read.
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve, isAbsolute, win32 } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const home = process.env.BURN_MY_USAGE_HOME || resolve(process.env.HOME || homedir(), '.burn-my-usage');
const lock = resolve(home, 'run.lock');
// A shell supervisor requires a positive completion token; empty early exits are failures.
const supervised = process.argv.length === 3 && process.argv[2] === '--supervised';
function allow() {
  if (supervised) console.log('BMU_CODEX_ALLOW_V1');
  process.exit(0);
}
function deny(reason) {
  console.log(supervised ? 'BMU_CODEX_DENY_V1' : JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',permissionDecision:'deny',permissionDecisionReason:`burn-my-usage guard: ${reason}`}}));
  process.exit(0);
}
if (process.argv.length > 2 && !supervised) deny('invalid supervisor mode');
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_-]+$/.test(id);
let event;
try { event = JSON.parse(readFileSync(0, 'utf8')); } catch {}
const marked = validId(event?.session_id) && existsSync(resolve(home, 'active', 'codex', event.session_id));
if (!existsSync(lock)) {
  if (marked) deny('active run lock missing');
  allow();
}
let owner;
try { owner = readFileSync(resolve(lock, 'owner'), 'utf8').split(/\r?\n/); }
catch { deny('cannot read active run identity'); }
if (!['codex', 'claude-code'].includes(owner[0]) || !validId(owner[1])) deny('invalid active run identity');
if (owner[0] !== 'codex') {
  if (marked) deny('active run owner mismatch');
  allow();
}
if (!event || Array.isArray(event) || !validId(event.session_id)) deny('invalid native session identity');
// Native child events carry their parent session_id. A different session is unaffected.
if (event.session_id !== owner[1]) {
  if (marked) deny('active run owner mismatch');
  allow();
}
if (!marked) deny('active run marker missing');
if (event.hook_event_name !== 'PreToolUse' || typeof event.cwd !== 'string' ||
    !(isAbsolute(event.cwd) || win32.isAbsolute(event.cwd)) || typeof event.tool_name !== 'string' ||
    !event.tool_input || typeof event.tool_input !== 'object' || Array.isArray(event.tool_input)) deny('invalid native tool envelope');
const args = event.tool_input;
let tool = event.tool_name, input = args;
if (tool === 'Bash') {
  if (typeof args.command !== 'string' || !args.command) deny('invalid command input');
  if (args.shell !== undefined || args.env !== undefined) deny('unsupported shell override');
  // Never discard an override that affects how relative paths resolve.
  if (args.cwd !== undefined && args.workdir !== undefined && args.cwd !== args.workdir) deny('conflicting command directories');
  const dir = args.workdir ?? args.cwd;
  if (dir !== undefined && (typeof dir !== 'string' || !(isAbsolute(dir) || win32.isAbsolute(dir)))) deny('invalid command directory');
  tool = 'functions.exec_command'; input = {cmd:args.command, ...(dir === undefined ? {} : {workdir:dir})};
} else if (tool === 'apply_patch' || tool === 'functions.apply_patch') {
  if (typeof args.command !== 'string') deny('invalid patch input');
  // Patch is relative to the hook cwd; unrecognised overrides cannot be ignored.
  if (args.cwd !== undefined || args.workdir !== undefined) deny('unsupported patch directory override');
  tool = 'functions.apply_patch'; input = {patch:args.command};
}
let bash = process.env.BMU_BASH;
if (!bash && process.platform === 'win32') {
  try {
    const config = readFileSync(resolve(home, 'config.md'), 'utf8');
    const matches = [...config.matchAll(/^[ \t]*[-*]?[ \t]*codex_bash:[ \t]*(.*)$/gmi)];
    if (matches.length === 1) bash = matches[0][1].replace(/[ \t]+#.*$/, '').trim().replace(/^`(.*)`$/, '$1').replace(/^(['"])(.*)\1$/, '$2');
  } catch {}
}
if (process.platform === 'win32' && (!bash || !win32.isAbsolute(bash) || /[\r\n\x00"]/.test(bash))) deny('codex_bash must be an absolute Git Bash executable path');
const adapter = resolve(dirname(fileURLToPath(import.meta.url)), 'guard-codex.mjs');
const result = spawnSync(process.execPath, [adapter], {
  input:JSON.stringify({session_id:event.session_id,cwd:event.cwd,tool_name:tool,tool_input:input}),
  encoding:'utf8', timeout:12000, env:{...process.env, BMU_HOST:'codex', BMU_SESSION_ID:event.session_id, ...(bash ? {BMU_BASH:bash} : {})}
});
if (result.error || result.status !== 0) deny('Codex guard failed');
if (result.stdout.trim()) {
  try {
    const out = JSON.parse(result.stdout);
    if (out.hookSpecificOutput?.hookEventName !== 'PreToolUse' || out.hookSpecificOutput?.permissionDecision !== 'deny') throw Error();
  } catch { deny('invalid Codex guard response'); }
  if (supervised) console.log('BMU_CODEX_DENY_V1');
  else process.stdout.write(result.stdout);
} else {
  allow();
}
