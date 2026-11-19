// Optional Codex quota adapter. Stores only validated quota windows.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { collectQuota } from './codex-quota-transport.mjs';

const home = process.env.BURN_MY_USAGE_HOME || path.join(os.homedir(), '.burn-my-usage');
const file = path.join(home, 'usage', 'codex.json');
const now = () => Math.floor(Date.now() / 1000);
const validWindow = w => w && typeof w === 'object' &&
  typeof w.usedPercent === 'number' && Number.isFinite(w.usedPercent) &&
  w.usedPercent >= 0 && w.usedPercent <= 100 &&
  Number.isSafeInteger(w.windowDurationMins) && w.windowDurationMins > 0 &&
  Number.isSafeInteger(w.resetsAt) && w.resetsAt > now() &&
  w.resetsAt <= now() + w.windowDurationMins * 60 + 60;
const unknown = reason => { console.log('verdict=unknown'); console.log(`reason=${reason}`); };

let collected = false, freshSnapshot;
if (['ingest', 'collect', 'check'].includes(process.argv[2])) {
  try {
    let response;
    if (process.argv[2] !== 'ingest') response = await collectQuota();
    else {
      let input = '';
      for await (const chunk of process.stdin) {
        input += chunk;
        if (input.length > 1024 * 1024) throw Error('response too large');
      }
      response = JSON.parse(input);
    }
    const bucket = response?.method === 'account/rateLimits/updated'
      ? response.params?.rateLimits : response?.result?.rateLimits;
    if (!bucket || bucket.limitId !== 'codex') throw Error('missing codex bucket');
    if (bucket.rateLimitReachedType != null && typeof bucket.rateLimitReachedType !== 'string') throw Error('invalid reached state');
    const windows = [bucket.primary, bucket.secondary].filter(w => w != null);
    if (!windows.length || !windows.every(validWindow)) throw Error('invalid windows');
    const weekly = windows.filter(w => w.windowDurationMins === 10080);
    if (weekly.length !== 1 || windows.length !== 2 || windows.filter(w => w.windowDurationMins === 300).length !== 1) throw Error('missing or ambiguous quota windows');
    const snapshot = { provider: 'codex', source: 'app-server-account-rate-limits',
      capturedAt: now(), limitReached: bucket.rateLimitReachedType != null, windows: windows.map(w => ({ usedPercent: w.usedPercent,
        windowDurationMins: w.windowDurationMins, resetsAt: w.resetsAt })) };
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(snapshot) + '\n', { mode: 0o600 });
    fs.renameSync(tmp, file);
    freshSnapshot = snapshot;
    collected = true;
    if (process.argv[2] !== 'check') console.log('INGESTED: Codex quota snapshot');
  } catch {
    // A failed new observation must not leave an earlier observation usable.
    try { fs.unlinkSync(file); } catch { /* absent */ }
    if (process.argv[2] === 'check') unknown('Codex usage unavailable, stale or malformed');
    else { console.error('ERROR: invalid or unavailable Codex quota response'); process.exitCode = 1; }
  }
}
if (process.argv[2] === 'read' || (process.argv[2] === 'check' && collected)) {
  try {
    const config = fs.existsSync(path.join(home, 'config.md')) ? fs.readFileSync(path.join(home, 'config.md'), 'utf8') : '';
    const match = config.match(/^\s*[-*]?\s*stop_at:\s*([^\s#`]+)/m);
    const raw = process.argv[3] === '--stop-at' ? process.argv[4] : (match?.[1] || '90');
    if (!/^\d+(?:\.\d+)?%?$/.test(raw || '')) throw Error('invalid stop_at');
    const stop = Number(raw.replace(/%$/, ''));
    if (!(stop > 0 && stop < 100)) throw Error('invalid stop_at');
    const s = process.argv[2] === 'check' ? freshSnapshot : JSON.parse(fs.readFileSync(file, 'utf8'));
    if (s.provider !== 'codex' || s.source !== 'app-server-account-rate-limits' ||
        typeof s.limitReached !== 'boolean' ||
        !Number.isSafeInteger(s.capturedAt) || now() < s.capturedAt || now() - s.capturedAt > 3600 ||
        !Array.isArray(s.windows) || !s.windows.length || !s.windows.every(validWindow)) throw Error('invalid or stale snapshot');
    const weekly = s.windows.filter(w => w.windowDurationMins === 10080);
    if (weekly.length !== 1 || s.windows.length !== 2 || s.windows.filter(w => w.windowDurationMins === 300).length !== 1) throw Error('missing or ambiguous quota windows');
    const limiting = s.windows.reduce((a, b) => b.usedPercent > a.usedPercent ? b : a);
    const used = limiting.usedPercent;
    console.log(`stop_at=${stop}\nage_minutes=${Math.floor((now() - s.capturedAt) / 60)}\nweekly_used=${weekly[0].usedPercent}`);
    console.log(`limiting_window_minutes=${limiting.windowDurationMins}\nlimiting_used=${used}`);
    console.log(`weekly_resets_in_hours=${((weekly[0].resetsAt - now()) / 3600).toFixed(1)}`);
    console.log(`verdict=${s.limitReached || used >= stop ? 'stop' : used >= stop - 5 ? 'wrap' : 'go'}`);
    console.log(`reason=${s.limitReached ? 'Codex reports a reached quota limit' : `${used}% used against the ${stop}% stop line`}`);
  } catch (e) { unknown(e.message === 'invalid stop_at' ? e.message : 'Codex usage unavailable, stale or malformed'); }
} else if (!['ingest', 'collect', 'check'].includes(process.argv[2])) {
  console.error('Usage: node usage-codex.mjs ingest | collect | check | read');
  process.exitCode = 2;
}
