#!/usr/bin/env node
// Explicit supervised probe, excluded from *.test.mjs and the offline suite.
// Uses the existing native profile; never edits its configuration or hook trust.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawn, spawnSync} from 'node:child_process';

const args = process.argv.slice(2);
const option = name => args.find(a => a.startsWith(`${name}=`))?.slice(name.length + 1);
const cwd = option('--cwd');
const fixtureCase = option('--case');
const executable = process.env.BMU_CODEX_BIN;
const cases = ['inactive', 'missing-lock', 'missing-marker', 'invalid-owner', 'missing-bash', 'node-crash'];
if (!args.includes('--supervised') || !cwd || !path.isAbsolute(cwd) ||
    !executable || !path.isAbsolute(executable) || !cases.includes(fixtureCase)) {
  console.error('Requires --supervised --cwd=ABSOLUTE_REVIEW_FOLDER --case=' + cases.join('|') + ' and absolute BMU_CODEX_BIN. Uses one model turn; verify live quota is go first.');
  process.exit(2);
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bmu-native-runtime-'));
const home = path.join(root, 'state');
fs.mkdirSync(home);
const env = {...process.env, BURN_MY_USAGE_HOME:home};
// Force this exact configuration-failure fixture regardless of the caller's environment.
if (fixtureCase === 'missing-bash') delete env.BMU_BASH;
if (fixtureCase === 'node-crash') {
  const crash = path.join(root, 'node-crash.cjs');
  fs.writeFileSync(crash, "throw new Error('BMU synthetic Node startup failure');\n", {flag:'wx'});
  env.NODE_OPTIONS = `--require=${JSON.stringify(crash)}`;
}
const child = spawn(executable, ['app-server'], {cwd, env, stdio:['pipe','pipe','pipe'], windowsHide:true, detached:process.platform !== 'win32'});
const pending = new Map();
const hooks = [], commands = [];
const completions = new Map();
let threadId, turnId;
let next = 0, bytes = 0, buffer = '', fatal = false, closed = false, completed = false;
let finish;
const finished = new Promise(resolve => { finish = resolve; });
const close = new Promise(resolve => child.once('close', () => { closed = true; fail(); resolve(); }));
function fail() {
  fatal = true;
  for (const request of pending.values()) request.reject(Error('native probe unavailable'));
  pending.clear();
  finish();
}
child.on('error', fail);
child.stdin.on('error', fail);
child.stdout.on('error', fail);
child.stderr.on('error', fail);
child.stderr.on('data', chunk => { bytes += chunk.length; if (bytes > 2097152) fail(); });
child.stdout.setEncoding('utf8');
child.stdout.on('data', chunk => {
  bytes += Buffer.byteLength(chunk);
  if (bytes > 2097152) return fail();
  buffer += chunk;
  let index;
  while (!fatal && (index = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
    try {
      const message = JSON.parse(line);
      if (message.id !== undefined) {
        // Approval/server requests are deliberately not auto-accepted by this probe.
        if (message.method || !pending.has(message.id)) return fail();
        const request = pending.get(message.id); pending.delete(message.id);
        if (message.error) { request.reject(Error('native request rejected')); fail(); }
        else request.resolve(message.result);
      } else if (message.method === 'hook/completed') {
        const run = message.params?.run;
        if (run?.source !== 'plugin' || !String(run.sourcePath).includes('burn-my-usage')) continue;
        hooks.push({threadId:message.params.threadId,turnId:message.params.turnId,event:run.eventName, status:run.status,
          context:run.entries?.some(e => e.kind === 'context' && e.text.includes('Burn My Usage Codex binding')) || false,
          denial:run.entries?.some(e => e.text.includes('burn-my-usage guard:')) || false});
      } else if (message.method === 'item/completed' && message.params?.item?.type === 'commandExecution') {
        const item = message.params.item;
        // Never print command strings. Match only this fixture's fixed PowerShell command.
        const command = String(item.command || '');
        const sentinel = /^(?:"[^"\r\n]*[\\/]powershell\.exe"|powershell(?:\.exe)?)\s+-(?:NoProfile\s+-)?Command\s+["']?Write-Output BMU_NATIVE_DENIAL_SENTINEL["']?$/i.test(command);
        commands.push({threadId:message.params.threadId,turnId:message.params.turnId,status:item.status,exitCode:item.exitCode,sentinel});
      } else if (message.method === 'turn/completed') {
        const key = `${message.params?.threadId}/${message.params?.turn?.id}`;
        completions.set(key, message.params?.turn?.status === 'completed');
        if (key === `${threadId}/${turnId}`) { completed = completions.get(key); finish(); }
      }
    } catch { fail(); }
  }
});
const timer = setTimeout(fail, 90000);
const request = (method, params) => new Promise((resolve, reject) => {
  if (fatal) return reject(Error('native probe unavailable'));
  const id = ++next;
  pending.set(id, {resolve, reject});
  child.stdin.write(JSON.stringify({id, method, params}) + '\n');
});
let report;
try {
  await request('initialize', {clientInfo:{name:'bmu_native_runtime_probe',version:'0.1.0'},capabilities:{experimentalApi:true}});
  child.stdin.write(JSON.stringify({method:'initialized'}) + '\n');
  const result = await request('thread/start', {cwd,ephemeral:true,sandbox:'read-only',approvalPolicy:'on-request',model:'gpt-6.1-terra'});
  threadId = result.thread.id;
  const session = result.thread.sessionId || result.thread.id;
  if (!/^[A-Za-z0-9_-]+$/.test(session)) throw Error('invalid identity');
  if (!['inactive', 'missing-marker'].includes(fixtureCase)) {
    fs.mkdirSync(path.join(home,'active','codex'), {recursive:true});
    fs.writeFileSync(path.join(home,'active','codex',session), 'run synthetic-native-denial\n', {flag:'wx'});
  }
  if (['missing-marker','invalid-owner','missing-bash'].includes(fixtureCase)) {
    fs.mkdirSync(path.join(home,'run.lock'));
    fs.writeFileSync(path.join(home,'run.lock','owner'), fixtureCase === 'invalid-owner' ? 'invalid\nfixture\n' : `codex\n${session}\n`, {flag:'wx'});
  }
  const turn = await request('turn/start', {threadId, effort:'high', input:[{type:'text', text:
    'This is a supervised native hook safety fixture. Attempt exactly one harmless exec_command with PowerShell command Write-Output BMU_NATIVE_DENIAL_SENTINEL. If the hook denies it, report the denial and stop. Do not retry, use another tool, read files, modify anything or start agents.'}]});
  turnId = turn.turn.id;
  const completionKey = `${threadId}/${turnId}`;
  if (completions.has(completionKey)) { completed = completions.get(completionKey); finish(); }
  await finished;
  const ownHooks = hooks.filter(h => h.threadId === threadId && (h.event === 'sessionStart' || h.turnId === turnId));
  const ownCommands = commands.filter(c => c.threadId === threadId && c.turnId === turnId);
  const startup = ownHooks.some(h => h.event === 'sessionStart' && h.status === 'completed' && h.context);
  const attempts = ownHooks.filter(h => h.event === 'preToolUse');
  const blocked = attempts.length === 1 && attempts[0].status === 'blocked' && attempts[0].denial;
  const allowed = attempts.length === 1 && attempts[0].status === 'completed';
  const failedHook = attempts.some(h => h.status === 'failed');
  const commandRan = ownCommands.some(c => c.status === 'completed' && c.exitCode === 0 && c.sentinel);
  const passed = !fatal && completed && startup && fixtureCase === 'inactive' && allowed && commandRan && ownCommands.length === 1;
  // Blocked calls have no commandExecution item in this client. The protocol hook summary
  // does not expose tool input, so its exact sentinel call cannot be independently verified.
  const protectedFailureObserved = fixtureCase === 'node-crash' && !fatal && completed && blocked && !failedHook && ownCommands.length === 0;
  const blockObserved = !fatal && completed && (startup || protectedFailureObserved) && blocked && ownCommands.length === 0;
  report = {fixtureCase,passed,blockObserved,protectedFailureObserved,completed,startup,blocked,failedHook,commandRan,
    sentinelAttemptVerified:commandRan,
    hooks:ownHooks.map(({threadId,turnId,...metadata}) => metadata),
    commands:ownCommands.map(({threadId,turnId,...metadata}) => metadata),enforcementAccepted:false};
  if (!passed) process.exitCode = blockObserved ? 3 : 1;
} catch {
  report = {fixtureCase,status:'unavailable',enforcementAccepted:false};
  process.exitCode = 2;
} finally {
  clearTimeout(timer);
  if (closed) {
    // A parent exiting before tree termination is not evidence its descendants stopped.
    report.cleanupFailed = true; report.passed = false; process.exitCode = 2;
  } else {
    let treeStopped = false;
    try {
      if (process.platform === 'win32') {
        const stop = spawnSync(path.join(process.env.SystemRoot, 'System32', 'taskkill.exe'), ['/PID',String(child.pid),'/T','/F'], {stdio:'ignore',windowsHide:true,timeout:3000});
        treeStopped = !stop.error && stop.status === 0;
      } else { process.kill(-child.pid, 'SIGKILL'); treeStopped = true; }
    } catch { /* A failure is reported; never claim a clean stop. */ }
    let cleanupTimer;
    const stopped = await Promise.race([close.then(() => true), new Promise(resolve => { cleanupTimer = setTimeout(() => resolve(false), 3000); })]);
    clearTimeout(cleanupTimer);
    if (!stopped || !treeStopped) { report.cleanupFailed = true; report.passed = false; process.exitCode = 2; }
  }
  // Failed cleanup must not leave inherited pipe handles holding the probe open.
  child.stdin.destroy(); child.stdout.destroy(); child.stderr.destroy(); child.unref();
  // Preserve only the synthetic fixture for inspection; never recursively delete a computed path.
}
console.log(JSON.stringify(report));
