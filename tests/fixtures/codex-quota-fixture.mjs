import { copyFileSync, chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

// A synthetic `codex` that runs this Node. On Windows it is a copy of node.exe, which avoids
// command shims and shell execution there. Elsewhere a copy is not enough: some builds (such as
// Homebrew's on macOS) are a small launcher that loads libnode from beside it, so a lone copy
// cannot start. There it is a two-line script the kernel runs directly; no shell parses the
// test's arguments.
export function quotaFixture(dir, env = process.env) {
  const bin = join(dir, 'quota-bin'); mkdirSync(bin, { recursive: true });
  const executable = join(bin, process.platform === 'win32' ? 'codex.exe' : 'codex');
  if (process.platform === 'win32') copyFileSync(process.execPath, executable);
  else writeFileSync(executable, `#!/bin/sh\nexec '${process.execPath.replaceAll("'", "'\\''")}' "$@"\n`);
  chmodSync(executable, 0o755);
  const preload = fileURLToPath(new URL('./codex-quota-server.cjs', import.meta.url)).replaceAll('\\', '/');
  return { ...env, PATH: `${bin}${delimiter}${env.PATH || ''}`, NODE_OPTIONS: `--require="${preload}"` };
}
