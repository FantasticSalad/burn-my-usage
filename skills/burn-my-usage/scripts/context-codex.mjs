#!/usr/bin/env node
// Read-only native SessionStart context. No run is activated and no settings are edited.
import { readFileSync } from 'node:fs';
import { dirname, isAbsolute, resolve, win32 } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scripts = dirname(fileURLToPath(import.meta.url));
const warning = () => ({systemMessage:'Burn My Usage could not bind this Codex session. No run was started; native runtime acceptance remains required.'});

export function createContext(event, options = {}) {
  if (!event || Array.isArray(event) || event.hook_event_name !== 'SessionStart' ||
      typeof event.session_id !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(event.session_id) ||
      typeof event.cwd !== 'string' || /[\x00-\x1f]/.test(event.cwd) ||
      !(isAbsolute(event.cwd) || win32.isAbsolute(event.cwd))) return warning();
  const home = options.home || process.env.BURN_MY_USAGE_HOME || resolve(process.env.HOME || homedir(), '.burn-my-usage');
  const lines = [
    'Burn My Usage Codex binding (experimental; no run started):',
    `Native session ID: ${JSON.stringify(event.session_id)}.`,
    `Shared skill: ${JSON.stringify(resolve(scripts, '..', 'SKILL.md'))}.`,
    `Codex binding: ${JSON.stringify(resolve(scripts, '..', 'hosts', 'codex.md'))}.`,
    `Scripts: ${JSON.stringify(scripts)}.`,
    'Pass BMU_HOST=codex to each helper process and the native session ID as its explicit session argument; do not assume shell environment persists between calls.',
    'The guard bridge binds identity from native events. Installation and this context are not proof of hook enforcement or live quota refresh. Native unattended acceptance remains deferred; read-only modes and setup guidance stay available.'
  ];
  // A marker is a recovery pointer only. Never copy arbitrary marker text into model context.
  try {
    const marker = readFileSync(resolve(home, 'active', 'codex', event.session_id), 'utf8');
    const match = /^run ([A-Za-z0-9_-]{1,300})$/m.exec(marker);
    if (match) lines.push(`Saved queue pointer: ${JSON.stringify(resolve(home, 'runs', match[1], 'queue.md'))}. Re-read it before resuming and verify ownership; marker age is not authority.`);
  } catch { /* No matching marker is the usual case. */ }
  return {hookSpecificOutput:{hookEventName:'SessionStart',additionalContext:lines.join('\n')}};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let output;
  try {
    const raw = readFileSync(0, 'utf8');
    output = raw.length <= 262144 ? createContext(JSON.parse(raw)) : warning();
  } catch { output = warning(); }
  console.log(JSON.stringify(output));
}
