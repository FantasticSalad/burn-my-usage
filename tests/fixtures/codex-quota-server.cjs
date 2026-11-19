// Loaded only by synthetic tests; ordinary Node invocations continue normally.
if (process.env.BMU_TEST_QUOTA_MODE_FILE) {
  const fs = require('node:fs');
  if (fs.readFileSync(process.env.BMU_TEST_QUOTA_MODE_FILE, 'utf8').trim() === 'error-unlink-fail') {
    const unlink = fs.unlinkSync;
    fs.unlinkSync = function (p, ...args) {
      if (String(p).endsWith('codex.json')) throw new Error('synthetic unlink failure');
      return unlink.call(this, p, ...args);
    };
  }
}
if (process.argv[1] && /(?:^|[\\/])app-server$/.test(process.argv[1])) {
  require('node:module').runMain = () => {};
  const readline = require('node:readline');
  const fs = require('node:fs');
  readline.createInterface({ input: process.stdin }).on('line', line => {
    const m = JSON.parse(line);
    if (m.id === 1) process.stdout.write(JSON.stringify({ id: 1, result: {} }) + '\n');
    if (m.id === 2) {
      const mode = process.env.BMU_TEST_QUOTA_MODE_FILE && fs.readFileSync(process.env.BMU_TEST_QUOTA_MODE_FILE, 'utf8').trim();
      const now = Math.floor(Date.now() / 1000);
      const bucket = { limitId: 'codex', primary: { usedPercent: mode === 'stop' ? 100 : 10, windowDurationMins: 300, resetsAt: now + 1800 }, secondary: { usedPercent: 10, windowDurationMins: 10080, resetsAt: now + 3600 } };
      if (mode === 'missing') delete bucket.primary;
      if (mode === 'reached') bucket.rateLimitReachedType = 'synthetic-future-limit';
      process.stdout.write(JSON.stringify(mode && mode.startsWith('error') ? { id: 2, error: { message: 'synthetic' } } : { id: 2, result: { rateLimits: bucket } }) + '\n');
    }
  });
}
