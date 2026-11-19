// Fixed App Server protocol: no arbitrary methods, account data or raw diagnostics.
import { spawn } from 'node:child_process';
import path from 'node:path';

export function collectQuota({ spawnChild = () => {
  const executable = process.env.BMU_CODEX_BIN || 'codex';
  if (process.env.BMU_CODEX_BIN && !path.isAbsolute(executable)) throw new Error('absolute client path required');
  return spawn(executable, ['app-server'], {
  stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true
  });
}, timeoutMs = 15000, maxBytes = 1024 * 1024 } = {}) {
  return new Promise((resolve, reject) => {
    let child, timer, cleanupTimer, done = false, settled = false, bytes = 0, pending = '', phase = 'initialize';
    const settle = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(cleanupTimer);
      if (error) reject(new Error('Codex quota collection failed'));
      else resolve(result);
    };
    const finish = (error, result) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      if (!child) return settle(true);
      child.stdin.destroy();
      // A successful sample is usable only once the client confirms termination.
      cleanupTimer = setTimeout(() => settle(true), 2000);
      child.once('close', () => settle(error, result));
      try { if (!child.kill()) settle(true); } catch { settle(true); }
    };
    const send = message => child.stdin.write(JSON.stringify(message) + '\n');
    const handle = line => {
      let message;
      try { message = JSON.parse(line); } catch { return finish(true); }
      if (!message || typeof message !== 'object' || Array.isArray(message)) return finish(true);
      if (message.id === undefined) return; // Notifications are never used as samples.
      if (message.method !== undefined) return finish(true); // Refuse server requests.
      if (message.id !== (phase === 'initialize' ? 1 : 2) || message.error || !message.result || typeof message.result !== 'object') return finish(true);
      if (phase === 'initialize') {
        phase = 'quota';
        send({ method: 'initialized' });
        send({ id: 2, method: 'account/rateLimits/read' });
      } else {
        const result = message.result;
        const bucket = result.rateLimitsByLimitId == null ? result.rateLimits : result.rateLimitsByLimitId.codex;
        if (!bucket || bucket.limitId !== 'codex') return finish(true);
        finish(false, { result: { rateLimits: bucket } });
      }
    };
    try {
      child = spawnChild();
      timer = setTimeout(() => finish(true), timeoutMs);
      child.on('error', () => finish(true));
      child.on('close', () => { if (!done) { done = true; clearTimeout(timer); settle(true); } });
      child.stdin.on('error', () => finish(true));
      child.stdout.on('error', () => finish(true));
      child.stderr.on('error', () => finish(true));
      child.stderr.on('data', chunk => { bytes += chunk.length; if (bytes > maxBytes) finish(true); });
      child.stdout.on('data', chunk => {
        bytes += chunk.length;
        if (bytes > maxBytes) return finish(true);
        pending += chunk.toString('utf8');
        let index;
        while (!done && (index = pending.indexOf('\n')) !== -1) {
          const line = pending.slice(0, index); pending = pending.slice(index + 1);
          handle(line);
        }
      });
      send({ id: 1, method: 'initialize', params: { clientInfo: { name: 'burn-my-usage', version: '0.1.0' } } });
    } catch { finish(true); }
  });
}
