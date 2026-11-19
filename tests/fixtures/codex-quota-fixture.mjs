import { copyFileSync, chmodSync, mkdirSync } from 'node:fs';
import { join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

// A copied Node executable avoids platform-specific command shims or shell execution.
export function quotaFixture(dir, env = process.env) {
  const bin = join(dir, 'quota-bin'); mkdirSync(bin, { recursive: true });
  const executable = join(bin, process.platform === 'win32' ? 'codex.exe' : 'codex');
  copyFileSync(process.execPath, executable); chmodSync(executable, 0o755);
  const preload = fileURLToPath(new URL('./codex-quota-server.cjs', import.meta.url)).replaceAll('\\', '/');
  return { ...env, PATH: `${bin}${delimiter}${env.PATH || ''}`, NODE_OPTIONS: `--require="${preload}"` };
}
