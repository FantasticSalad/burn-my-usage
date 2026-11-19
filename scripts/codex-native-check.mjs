#!/usr/bin/env node
// Read-only discovery diagnostic. A pass is not tool-enforcement acceptance.
import { spawn } from 'node:child_process';
import { isAbsolute, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function assessNative(hooksResult, skillsResult, pluginId) {
  const hooks = (hooksResult.data || []).flatMap(e => e.hooks || []).filter(h => h.pluginId === pluginId);
  const name = pluginId.split('@')[0];
  const skills = (skillsResult.data || []).flatMap(e => e.skills || []).filter(s => s.name === `${name}:burn-my-usage`);
  const events = ['sessionStart', 'preToolUse'].map(event => ({
    event, discovered: hooks.some(h => h.eventName === event),
    enabledAndTrusted: hooks.some(h => h.eventName === event && h.enabled && h.trustStatus === 'trusted')
      && hooks.filter(h => h.eventName === event).every(h => h.enabled && h.trustStatus === 'trusted')
  }));
  const errorCount = [...(hooksResult.data || []), ...(skillsResult.data || [])].reduce((n, e) => n + (e.errors?.length || 0), 0);
  const ready = skills.some(s => s.enabled) && events.every(e => e.enabledAndTrusted) && errorCount === 0;
  const relatedHooks = (hooksResult.data || []).flatMap(e => e.hooks || []).filter(h =>
    String(h.pluginId || '').includes(name) || String(h.sourcePath || '').includes(name)).map(h =>
    ({pluginId:h.pluginId,event:h.eventName,enabled:h.enabled,trust:h.trustStatus}));
  return {status: ready ? 'ready-for-enforcement-tests' : 'blocked', skillDiscovered: skills.some(s => s.enabled), events, relatedHooks, errorCount,
    enforcementAccepted: false, message: 'Discovery and trust do not prove denial, hook failure handling, child coverage or safe continuation.'};
}

export async function inspectNative(cwd, pluginId = 'burn-my-usage@burn-my-usage-local') {
  const executable = process.env.BMU_CODEX_BIN || 'codex';
  if (process.env.BMU_CODEX_BIN && !isAbsolute(executable)) throw Error('native diagnostic failed');
  const child = spawn(executable, ['app-server'], {cwd, stdio:['pipe', 'pipe', 'pipe'], windowsHide:true});
  const pending = new Map();
  let id = 0, bytes = 0, buffer = '', fatal, closed = false;
  const fail = () => {
    fatal = true;
    for (const request of pending.values()) request.reject(Error('native diagnostic failed'));
    pending.clear();
  };
  const close = new Promise(resolveClose => child.once('close', () => { closed = true; fail(); resolveClose(); }));
  const deadline = setTimeout(fail, 20000);
  child.on('error', fail);
  child.stdin.on('error', fail);
  child.stdout.on('error', fail);
  child.stderr.on('error', fail);
  child.stderr.on('data', chunk => { bytes += chunk.length; if (bytes > 1048576) fail(); });
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', chunk => {
    bytes += Buffer.byteLength(chunk);
    if (bytes > 1048576) return fail();
    buffer += chunk;
    let index;
    while (!fatal && (index = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
      try {
        const message = JSON.parse(line);
        if (!message || typeof message !== 'object' || Array.isArray(message)) return fail();
        if (message.id === undefined) continue;
        if (message.method || !pending.has(message.id)) return fail();
        const request = pending.get(message.id); pending.delete(message.id);
        if (message.error || !message.result || typeof message.result !== 'object') {
          request.reject(Error('native diagnostic failed')); fail();
        } else request.resolve(message.result);
      } catch { fail(); }
    }
  });
  const request = (method, params) => new Promise((resolveReply, reject) => {
    if (fatal) return reject(Error('native diagnostic failed'));
    const next = ++id;
    pending.set(next, {resolve:resolveReply, reject});
    child.stdin.write(JSON.stringify({id:next, method, params}) + '\n');
  });
  let result, error;
  try {
    await request('initialize', {clientInfo:{name:'burn_my_usage_native_check',version:'0.1.0'},capabilities:{experimentalApi:true}});
    child.stdin.write(JSON.stringify({method:'initialized'}) + '\n');
    const hooks = await request('hooks/list', {cwds:[cwd]});
    const skills = await request('skills/list', {cwds:[cwd],forceReload:true});
    result = assessNative(hooks, skills, pluginId);
  } catch { error = true; }
  finally {
    clearTimeout(deadline);
    child.stdin.destroy();
    let cleanupTimer;
    if (!closed) {
      try { if (!child.kill()) error = true; } catch { error = true; }
      const stopped = await Promise.race([close.then(() => true), new Promise(resolveWait => { cleanupTimer = setTimeout(() => resolveWait(false), 2000); })]);
      clearTimeout(cleanupTimer);
      if (!stopped) error = true;
    }
  }
  if (error) throw Error('native diagnostic failed');
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const result = await inspectNative(resolve(process.argv[2] || '.'), process.argv[3]);
    console.log(JSON.stringify(result, null, 2));
    if (result.status === 'blocked') process.exitCode = 1;
  } catch {
    console.log(JSON.stringify({status:'unavailable',enforcementAccepted:false,message:'Native diagnostic failed; no runtime acceptance follows.'}));
    process.exitCode = 2;
  }
}
