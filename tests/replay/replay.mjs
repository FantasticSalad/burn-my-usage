#!/usr/bin/env node
// Replays the tool calls in Claude Code transcripts through guard.sh, as if a burn run had been
// active in every session, and counts what the guard would have refused. It costs no plan
// usage and answers two questions: which refusals are false positives (bugs in the guard), and
// what a run would be stopped from doing that the sessions really did.
//
//   bash tests/replay/run.sh [options] [transcript files or folders]
//
// Explicit fixture folders are searched for *.jsonl; no native history is searched. Tool calls are
// de-duplicated by id, because a resumed or moved session can leave copies of a transcript.
//
// Options:
//   --out DIR              results folder (default: a new temp folder). results.jsonl holds
//                          every refused call in full, so keep it out of any repo: transcripts
//                          hold whatever the sessions saw. summary.md holds counts only.
//   --roots LIST           comma-separated folders for roots.txt (default: none, so the scope
//                          check is off)
//   --map OLD=NEW          a folder that has moved since the transcripts were written
//                          (repeatable), e.g. --map ~/old-code=~/code
//   --rename-branch OLD=NEW  a branch prefix to rewrite in tool inputs, e.g. auto/=burn/
//   --run-skill NAME       a run starts when a session invokes this skill; its calls are
//                          labelled NAME (repeatable)
//   --run-prompt LABEL=RE  a run starts at a prompt matching RE (case-insensitive) (repeatable)
//   --continue-prompt RE   prompts that carry a run on (default: continue, keep going, ...).
//                          Any other prompt ends the run: the person is back and directing.
//   --since YYYY-MM-DD     skip tool calls before this date
//   --until TIMESTAMP      skip tool calls after this ISO time, so runs compare like for like
//   --limit N              replay only the first N tool calls
//   --jobs N               guard processes at once (default 8)
//   --bash PATH            the bash that runs the guard (run.sh passes Git Bash on Windows)
//   --guard PATH           the guard to test (default: this checkout's)
//
// The guard asks git which branch each repository is on now, not when the transcript was
// written, so each refused commit is checked against what really happened. git's own output
// names the branch ("[branch sha] subject"); failing that, a sha in the output (from a
// following git log --oneline) is looked up in the repository: on the default branch's
// first-parent line it was committed there, and otherwise the merge that brought it in names
// its branch. summary.md counts where each one landed: a burn-like branch, the default branch,
// another branch, or unknown. A commit that landed on a burn-like branch is a replay artifact,
// not a refusal a real run would have hit.
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SESSION = 'replay';
const PREFIX = 'burn-my-usage guard: ';
// How a refusal by a live guard starts a transcript's tool result. Output that merely prints
// guard text (a test run, cat guard.sh, a grep of an old transcript) starts some other way.
const LIVE = /^(?:\S+ hook error: )?burn-my-usage guard: /;
const SUFFIX = ' (a burn run is active in this session; /burn-my-usage stop ends it)';
const TIMEOUT_MS = 15000; // hooks/hooks.json gives the guard 15 seconds

const die = (msg) => {
  process.stderr.write(`replay: ${msg}\n`);
  process.exit(2);
};

function usage() {
  const src = readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n');
  const head = src.slice(1, src.findIndex((l, i) => i > 0 && !l.startsWith('//')));
  process.stdout.write(head.map((l) => l.replace(/^\/\/ ?/, '')).join('\n') + '\n');
}

function parseArgs(argv) {
  const o = {
    out: '', roots: [], maps: [], renames: [], runSkills: [], runPrompts: [], since: '', until: '', limit: 0, jobs: 8,
    continuePrompt: /^\s*(continue|keep going|carry on|go on|resume)\b/i,
    bash: 'bash', guard: resolve(here, '../../skills/burn-my-usage/scripts/guard.sh'), paths: [],
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => (i + 1 < argv.length ? argv[++i] : die(`${a} needs a value`));
    const pair = () => {
      const v = val();
      const k = v.indexOf('=');
      return k > 0 ? [v.slice(0, k), v.slice(k + 1)] : die(`${a} takes OLD=NEW, not ${v}`);
    };
    switch (a) {
      case '--out': o.out = val(); break;
      case '--roots': o.roots = val().split(',').map((s) => s.trim()).filter(Boolean); break;
      case '--map': o.maps.push(pair()); break;
      case '--rename-branch': o.renames.push(pair()); break;
      case '--run-skill': o.runSkills.push(val()); break;
      case '--run-prompt': { const [k, v] = pair(); o.runPrompts.push([k, new RegExp(v, 'i')]); break; }
      case '--continue-prompt': o.continuePrompt = new RegExp(val(), 'i'); break;
      case '--since': o.since = val(); break;
      case '--until': o.until = val(); break;
      case '--limit': o.limit = Number(val()); break;
      case '--jobs': o.jobs = Math.max(1, Number(val()) || 1); break;
      case '--bash': o.bash = val(); break;
      case '--guard': o.guard = resolve(val()); break;
      case '-h': case '--help': usage(); process.exit(0); break;
      default:
        if (a.startsWith('-')) die(`unknown option ${a}`);
        o.paths.push(a);
    }
  }
  if (!o.paths.length) die('provide explicitly sanitised exported fixture paths');
  return o;
}

const opts = parseArgs(process.argv.slice(2));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// --- rewriting tool inputs ------------------------------------------------------------------

// A folder as a regex matching it in any spelling a transcript might hold: C:\x, C:/x, /c/x,
// doubled backslashes, any case, and under the home folder ~/x, $HOME/x, $env:USERPROFILE\x and
// %USERPROFILE%\x. A match must end at a separator, quote, space or the end, so x/Code doesn't
// match x/CodeData.
function folderRe(folder) {
  const home = homedir();
  const abs = folder.startsWith('~') ? join(home, folder.slice(1)) : folder;
  const parts = abs.split(/[\\/]+/).filter(Boolean);
  const S = '[\\\\/]+';
  const alts = [];
  const drive = /^([A-Za-z]):$/.exec(parts[0]);
  if (drive) alts.push(`(?:${drive[1]}:|/${drive[1]})${S}${parts.slice(1).map(esc).join(S)}`);
  else alts.push(`${S}${parts.map(esc).join(S)}`);
  const hp = home.split(/[\\/]+/).filter(Boolean);
  const under = hp.every((p, i) => (parts[i] || '').toLowerCase() === p.toLowerCase());
  if (under && parts.length > hp.length) {
    alts.push(`(?:~|\\$HOME|\\$\\{HOME\\}|\\$env:USERPROFILE|%USERPROFILE%)${S}${parts.slice(hp.length).map(esc).join(S)}`);
  }
  return new RegExp(`(?:${alts.join('|')})(?=[\\\\/"'\\s;:|&)]|$)`, 'gi');
}

const folderRules = opts.maps.map(([from, to]) => {
  const fwd = to.replace(/\\/g, '/');
  const d = /^([A-Za-z]):(\/.*)?$/.exec(fwd);
  return { re: folderRe(from), fwd, back: fwd.replace(/\//g, '\\'), msys: d ? `/${d[1].toLowerCase()}${d[2] || ''}` : fwd };
});
const branchRules = opts.renames.map(([from, to]) => ({
  re: new RegExp(`(^|[\\s'"=:]|origin/|heads/|remotes/)${esc(from)}(?=[^\\s'"])`, 'g'),
  to,
}));

function rewrite(s) {
  for (const r of folderRules) s = s.replace(r.re, (m) => (m.includes('\\') ? r.back : m.startsWith('/') ? r.msys : r.fwd));
  for (const r of branchRules) s = s.replace(r.re, (_, pre) => pre + r.to);
  return s;
}

function deepRewrite(v) {
  if (typeof v === 'string') return rewrite(v);
  if (Array.isArray(v)) return v.map(deepRewrite);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, deepRewrite(x)]));
  return v;
}

// --- reading transcripts --------------------------------------------------------------------

function* walk(p) {
  const st = statSync(p);
  if (st.isFile()) {
    if (p.endsWith('.jsonl')) yield p;
    return;
  }
  for (const e of readdirSync(p)) yield* walk(join(p, e));
}

// A subagent's transcript lives in <session>/subagents/, and belongs to that session.
function sessionOf(file) {
  const parts = file.split(/[\\/]/);
  const i = parts.lastIndexOf('subagents');
  return i > 0 ? parts[i - 1] : parts[parts.length - 1].replace(/\.jsonl$/, '');
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n');
  return '';
}

const calls = new Map(); // tool_use id -> call
const results = new Map(); // tool_use id -> { error, text }
const sessions = new Map(); // session id -> { events: [timestamp, 'prompt' | 'skill', text] }
let files = 0;
let dups = 0;
let badLines = 0;

for (const p of opts.paths) {
  for (const file of walk(resolve(p.replace(/^~(?=$|[\\/])/, homedir())))) {
    files++;
    const key = sessionOf(file);
    if (!sessions.has(key)) sessions.set(key, { events: [] });
    const s = sessions.get(key);
    const lines = readFileSync(file, 'utf8').split('\n');
    for (let n = 0; n < lines.length; n++) {
      if (!lines[n]) continue;
      let o;
      try {
        o = JSON.parse(lines[n]);
      } catch {
        badLines++;
        continue;
      }
      const content = o.message?.content;
      if (o.type === 'assistant' && Array.isArray(content)) {
        for (const b of content) {
          if (b?.type !== 'tool_use') continue;
          if (b.name === 'Skill' && typeof b.input?.skill === 'string' && !o.isSidechain) {
            s.events.push([o.timestamp || '', 'skill', b.input.skill.split(':').pop()]);
          }
          if (calls.has(b.id)) {
            dups++;
            continue;
          }
          calls.set(b.id, {
            id: b.id, session: key, file, line: n + 1, ts: o.timestamp || '', cwd: o.cwd || '',
            gitBranch: o.gitBranch || '', tool: b.name, input: b.input || {},
          });
        }
      } else if (o.type === 'user') {
        if (Array.isArray(content)) {
          for (const b of content) {
            if (b?.type === 'tool_result' && !results.has(b.tool_use_id)) {
              // The start says whether a live guard refused it; the end usually holds the sha.
              const t = textOf(b.content);
              results.set(b.tool_use_id, { error: !!b.is_error, text: t.length > 6000 ? `${t.slice(0, 3000)}\n${t.slice(-3000)}` : t });
            }
          }
        }
        if (!o.isMeta && !o.isSidechain) {
          const t = textOf(content).trim();
          const cmd = /<command-name>\/?([^<\s]+)<\/command-name>/.exec(t);
          if (cmd) s.events.push([o.timestamp || '', 'skill', cmd[1].split(':').pop()]);
          else if (t && !t.startsWith('<') && !t.startsWith('[Request interrupted')) s.events.push([o.timestamp || '', 'prompt', t]);
        }
      }
    }
  }
}

// A session's phases: [start time, label]. A run starts at a run skill or a run prompt and
// lasts through continue prompts; any other prompt hands the session back to the person.
for (const s of sessions.values()) {
  s.events.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  let label = 'other';
  s.phases = [];
  for (const [ts, type, text] of s.events) {
    if (type === 'skill') {
      if (opts.runSkills.includes(text)) label = text;
    } else {
      const run = opts.runPrompts.find(([, re]) => re.test(text));
      if (run) label = run[0];
      else if (!(label !== 'other' && opts.continuePrompt.test(text))) label = 'other';
    }
    s.phases.push([ts, label]);
  }
}

function kindOf(call) {
  let label = 'other';
  for (const [ts, l] of sessions.get(call.session).phases) {
    if (ts > call.ts) break;
    label = l;
  }
  return label;
}

let todo = [...calls.values()].filter((c) => (!opts.since || c.ts >= opts.since) && (!opts.until || c.ts <= opts.until)).sort((a, b) => (a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : 0));
if (opts.limit > 0) todo = todo.slice(0, opts.limit);

// --- the burn home the guard sees ------------------------------------------------------------

const out = opts.out ? resolve(opts.out) : mkdtempSync(join(tmpdir(), 'bmu-replay-'));
const home = join(out, 'home');
mkdirSync(join(home, 'active'), { recursive: true });
writeFileSync(join(home, 'active', SESSION), '');
writeFileSync(join(home, 'INBOX.md'), '# Inbox\n');
writeFileSync(join(home, 'guard.log'), '');
if (opts.roots.length) writeFileSync(join(home, 'roots.txt'), opts.roots.join('\n') + '\n');
const fwd = (p) => p.replace(/\\/g, '/');

function runGuard(input) {
  return new Promise((done) => {
    const t0 = process.hrtime.bigint();
    const child = spawn(opts.bash, [fwd(opts.guard)], {
      env: { ...process.env, BURN_MY_USAGE_HOME: fwd(home) },
      windowsHide: true,
    });
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, TIMEOUT_MS);
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('error', (e) => die(`could not start ${opts.bash}: ${e.message}`));
    child.on('close', (code) => {
      clearTimeout(timer);
      done({ code, timedOut, stdout, stderr, ms: Number(process.hrtime.bigint() - t0) / 1e6 });
    });
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify(input));
  });
}

function decide(r) {
  if (r.timedOut) return { decision: 'timeout' };
  if (r.code !== 0) return { decision: 'error', detail: (r.stderr || r.stdout).slice(0, 400) };
  const s = r.stdout.trim();
  if (!s) return { decision: 'allow' };
  try {
    const h = JSON.parse(s).hookSpecificOutput;
    if (h?.permissionDecision === 'deny') {
      let why = h.permissionDecisionReason || '';
      if (why.startsWith(PREFIX)) why = why.slice(PREFIX.length);
      if (why.endsWith(SUFFIX)) why = why.slice(0, -SUFFIX.length);
      return { decision: 'deny', reason: why };
    }
  } catch {
    // Claude Code can't read output that isn't JSON, so the refusal wouldn't happen.
    return { decision: 'bad-output', detail: s.slice(0, 400) };
  }
  return { decision: 'bad-output', detail: s.slice(0, 400) };
}

// --- naming refusals ------------------------------------------------------------------------

// One id per refusal message in guard.sh, most specific first.
const RULES = [
  [/self-test OK/, 'self-test'],
  [/^the redirect writes .* outside the folders/, 'scope: shell redirect'],
  [/^the redirect writes .* agent, CI or git configuration/, 'config: shell redirect'],
  [/is outside the folders this run may change/, 'scope: file tool'],
  [/is agent, CI or git configuration/, 'config: file tool'],
  [/looks like a secret or credential file/, 'secrets: file'],
  [/adds a ticked box to INBOX\.md/, 'inbox: tick'],
  [/INBOX\.md, the run markers and the guard's files/, 'inbox/controls: from the shell'],
  [/^(git \S+) is only allowed on a burn\/ branch/, (m) => `branch: ${m[1]} off burn/`],
  [/^git push .* is not allowed\. Push one burn/, 'push: flag (force, all, tags...)'],
  [/^git push .* is not allowed in a burn run/, 'push: option'],
  [/a force push/, 'push: force'],
  [/may only push to burn\/ branches/, 'push: not a burn/ branch'],
  [/^name the branch when pushing/, 'push: no branch named'],
  [/skips the repository's hooks/, 'git: skips hooks'],
  [/^git -c /, 'git: -c override'],
  [/without --ff-only can create commits/, 'merge/pull: not ff-only'],
  [/needs a ticked Merge on its card/, 'merge: burn/ branch not approved'],
  [/^the only merges allowed onto a non-burn branch/, 'merge: not a burn/ branch'],
  [/^git reset --hard/, 'git: reset --hard'],
  [/^git clean/, 'git: clean -f'],
  [/discards (uncommitted work|every uncommitted change)/, 'git: discards changes'],
  [/resets an existing branch/, 'git: resets a branch'],
  [/^git stash drop\/clear/, 'git: stash drop'],
  [/^git branch with delete, move or force/, 'git: deletes or moves a branch'],
  [/^deleting or moving tags/, 'git: tags'],
  [/rewrites or prunes history/, 'git: rewrites history'],
  [/^git reflog/, 'git: reflog'],
  [/^git config changes/, 'git: config write'],
  [/^git remote/, 'git: remote change'],
  [/^git credential/, 'secrets: git credential'],
  [/^gh /, 'outward: gh write'],
  [/runs as another user/, 'machine: sudo'],
  [/reaches another machine/, 'outward: ssh/scp/rsync'],
  [/deploys or changes cloud resources/, 'outward: cloud CLI'],
  [/can change live infrastructure/, 'outward: infrastructure'],
  [/(publishes|nuget push)/, 'outward: publish'],
  [/(installing global packages|changes the machine, not the repo)/, 'machine: install'],
  [/schedules jobs or changes the machine/, 'machine: scheduler'],
  [/sending data out/, 'outward: http send'],
  [/(printenv|prints every variable|listing environment variables)/, 'secrets: env dump'],
  [/reads stored secrets/, 'secrets: secret store'],
  [/reads stored credentials/, 'secrets: stored credentials'],
  [/touches Claude Code settings or git hooks/, 'config: settings or hooks'],
  [/piping a download into a shell/, 'outward: curl | sh'],
  [/expands (an environment variable|a variable) that looks like a secret/, 'secrets: secret variable'],
  [/in guard-deny\.txt/, 'deny list'],
  [/nested more than three shells deep/, 'shell: nested too deep'],
  [/could not read the command/, 'shell: unreadable'],
  [/the user is away/, 'tools: asks the user'],
  [/acts outside this machine or schedules more work/, 'tools: outward tool'],
  [/looks like it changes something outside this machine/, 'tools: MCP write'],
  [/^(rm|Remove-Item|rmdir|rimraf|find) (deletes|-exec|-delete)|^find -delete|^find -exec|rimraf deletes|deletes a folder tree/, 'deletes: recursive'],
  [/git worktree remove --force/, 'git: worktree remove --force'],
  [/control byte the guard uses/, 'shell: control byte'],
];

function ruleOf(reason) {
  for (const [re, id] of RULES) {
    const m = re.exec(reason);
    if (m) return typeof id === 'function' ? id(m) : id;
  }
  return 'unnamed';
}

const burnLike = (b) => /^(?:origin\/)?burn\//.test(b) || opts.renames.some(([from]) => b.replace(/^origin\//, '').startsWith(from));
const where = (names) => (names.every(burnLike) ? 'burn' : names.some((b) => /^(?:origin\/)?(main|master)$/.test(b)) ? 'default' : 'other');

// Where git says the work went: commit lines ("[branch sha] subject"), push lines
// ("abc..def  src -> dst") or a finished rebase ("updated refs/heads/x").
function landedOf(res) {
  const t = res?.text || '';
  let names = [...t.matchAll(/^\[([^\s\]]+)(?: \(root-commit\))? [0-9a-f]{7,40}\]/gm)].map((x) => x[1]);
  if (!names.length) {
    names = [...t.matchAll(/^\s*[-+*!= ]?\s*(?:\[new branch\]|\+?[0-9a-f]{7,}\.\.\.?[0-9a-f]{7,})\s+\S+\s+->\s+(\S+)/gm)].map((x) => x[1]);
  }
  if (!names.length) names = [...t.matchAll(/updated refs\/heads\/(\S+?)\.?$/gm)].map((x) => x[1]);
  return names.length ? where(names) : 'unknown';
}

const gitOut = (dir, args) => {
  const r = spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8', windowsHide: true });
  return r.status === 0 ? r.stdout.trim() : null;
};
const gitCache = new Map();

// A commit whose output named no branch: look its sha up in the repository the guard judged.
function landedInRepo(reason, text) {
  const dm = /, and (.+?) is on /.exec(reason);
  // git log --oneline ("abc1234 subject") or a bare sha (git log -1 --format=%h).
  const shas = [...(text || '').matchAll(/^([0-9a-f]{7,40})(?:\s|$)/gm)].map((x) => x[1]);
  if (!dm || !shas.length) return 'unknown';
  const dir = dm[1];
  // git log lists the newest commit first, and the log usually follows the commit.
  const sha = shas[0];
  const key = `${dir}\n${sha}`;
  if (gitCache.has(key)) return gitCache.get(key);
  let ans = 'unknown';
  const full = gitOut(dir, ['rev-parse', '-q', '--verify', `${sha}^{commit}`]);
  if (full) {
    const def = ['origin/HEAD', 'origin/main', 'main', 'origin/master', 'master'].find((r) => gitOut(dir, ['rev-parse', '-q', '--verify', r]));
    if (def && gitOut(dir, ['merge-base', '--is-ancestor', full, def]) !== null) {
      const firstParent = gitOut(dir, ['rev-list', '--first-parent', def]) || '';
      if (firstParent.split('\n').includes(full)) ans = 'default';
      else {
        // The oldest first-parent commit after it is the merge that brought it in.
        const subjects = (gitOut(dir, ['log', '--ancestry-path', '--first-parent', '--format=%s', `${full}..${def}`]) || '').split('\n');
        const merge = subjects[subjects.length - 1] || '';
        if (merge.split(/[\s'":,()]+/).some(burnLike)) ans = 'burn';
        else {
          const names = [...merge.matchAll(/'([^']+)'/g)].map((x) => x[1]);
          ans = names.length ? where(names) : 'other';
        }
      }
    } else {
      const refs = (gitOut(dir, ['for-each-ref', '--contains', full, '--format=%(refname:short)', 'refs/heads', 'refs/remotes']) || '').split('\n').filter(Boolean);
      if (refs.length) ans = where(refs);
    }
  }
  gitCache.set(key, ans);
  return ans;
}

// --- replay ---------------------------------------------------------------------------------

const refused = [];
const tally = new Map(); // kind -> stats
const latency = new Map(); // tool group -> ms[]
const stat = (kind) => {
  if (!tally.has(kind)) {
    tally.set(kind, { sessions: new Set(), calls: 0, deny: 0, timeout: 0, error: 0, badOutput: 0, rules: new Map(), agree: { both: 0, replayOnly: 0, liveOnly: 0 } });
  }
  return tally.get(kind);
};
const group = (tool) => (tool === 'Bash' || tool === 'PowerShell' ? tool : /^(Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob)$/.test(tool) ? 'file tools' : 'other tools');

let doneCount = 0;
const started = Date.now();

async function replay(call) {
  const kind = kindOf(call);
  const input = {
    session_id: SESSION,
    transcript_path: '',
    cwd: rewrite(call.cwd),
    permission_mode: 'auto',
    hook_event_name: 'PreToolUse',
    tool_name: call.tool,
    tool_input: deepRewrite(call.input),
  };
  const r = await runGuard(input);
  const d = decide(r);
  const st = stat(kind);
  st.sessions.add(call.session);
  st.calls++;
  const g = group(call.tool);
  if (!latency.has(g)) latency.set(g, []);
  latency.get(g).push(r.ms);
  const res = results.get(call.id);
  const live = LIVE.test(res?.text || '');
  if (d.decision === 'deny') {
    if (live) st.agree.both++;
    else st.agree.replayOnly++;
  } else if (live) st.agree.liveOnly++;
  // Calls the live guard refused and the replay doesn't are kept too: each is a fix to confirm.
  if (d.decision === 'allow' && !live) return;
  if (d.decision === 'timeout') st.timeout++;
  if (d.decision === 'error') st.error++;
  if (d.decision === 'bad-output') st.badOutput++;
  if (d.decision === 'deny') st.deny++;
  const rule = d.decision === 'deny' ? ruleOf(d.reason) : d.decision === 'allow' ? 'live only' : d.decision;
  const landed = /^(branch|push|merge)/.test(rule) ? landedOf(res) : '';
  // The input as the guard saw it, after --map and --rename-branch. The transcript has the original.
  const shown = { ...input.tool_input };
  if (typeof shown.content === 'string' && shown.content.length > 400) shown.content = shown.content.slice(0, 400) + ' [...]';
  refused.push({
    id: call.id, kind, session: call.session, file: call.file, line: call.line, ts: call.ts, tool: call.tool,
    cwd: input.cwd, gitBranch: call.gitBranch, decision: d.decision, rule, reason: d.reason || d.detail || '',
    landed, live, input: shown, result: (res?.text || '').slice(0, 800),
  });
}

async function pool(items, n, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (next < items.length) {
      await fn(items[next++]);
      if (++doneCount % 500 === 0) process.stderr.write(`replay: ${doneCount}/${items.length} (${Math.round((Date.now() - started) / 1000)}s)\n`);
    }
  }));
}

await pool(todo, opts.jobs, replay);

for (const r of refused) {
  if (r.landed === 'unknown' && /^branch: git (commit|cherry-pick|revert|am)\b/.test(r.rule)) {
    r.landed = landedInRepo(r.reason, results.get(r.id)?.text);
  }
  if (r.decision !== 'deny') continue;
  const rules = stat(r.kind).rules;
  if (!rules.has(r.rule)) rules.set(r.rule, { n: 0, landed: {} });
  const rr = rules.get(r.rule);
  rr.n++;
  if (r.landed) rr.landed[r.landed] = (rr.landed[r.landed] || 0) + 1;
}

// --- report ---------------------------------------------------------------------------------

writeFileSync(join(out, 'results.jsonl'), refused.map((x) => JSON.stringify(x)).join('\n') + (refused.length ? '\n' : ''));

const pct = (a, b) => (b ? `${((100 * a) / b).toFixed(1)}%` : '-');
const q = (arr, p) => {
  if (!arr.length) return 0;
  const s = [...arr].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(p * s.length))];
};
const describe = spawnSync('git', ['-C', fwd(dirname(opts.guard)), 'describe', '--always', '--dirty'], { encoding: 'utf8' }).stdout.trim();
const range = todo.length ? `${todo[0].ts.slice(0, 10)} to ${todo[todo.length - 1].ts.slice(0, 10)}` : 'none';
const kinds = [...tally.keys()].sort((a, b) => (a === 'other') - (b === 'other') || a.localeCompare(b));

const md = [];
md.push('# Guard replay', '');
md.push(`- Guard: \`skills/burn-my-usage/scripts/guard.sh\` at \`${describe || 'unknown'}\``);
md.push(`- Transcripts: ${files} files, ${calls.size} unique tool calls (${dups} duplicates skipped, ${badLines} unreadable lines); replayed ${todo.length}, ${range}${opts.until ? ` (until ${opts.until})` : ''}`);
md.push(`- Roots: ${opts.roots.length ? opts.roots.map((r) => `\`${r}\``).join(', ') : 'none (scope not checked)'}`);
if (opts.maps.length) md.push(`- Moved folders: ${opts.maps.map(([a, b]) => `\`${a}\` to \`${b}\``).join(', ')}`);
if (opts.renames.length) md.push(`- Branch prefixes: ${opts.renames.map(([a, b]) => `\`${a}\` to \`${b}\``).join(', ')}`);
md.push(`- Parallel guard processes: ${opts.jobs}`, '');

md.push('## Sessions', '');
md.push('| Kind | Sessions | Tool calls | Refused | Share | Timeouts | Errors | Unreadable output |', '|---|---|---|---|---|---|---|---|');
for (const k of kinds) {
  const s = tally.get(k);
  md.push(`| ${k} | ${s.sessions.size} | ${s.calls} | ${s.deny} | ${pct(s.deny, s.calls)} | ${s.timeout} | ${s.error} | ${s.badOutput} |`);
}
md.push('');

md.push('## Refusals by rule', '');
md.push('Branch, push and merge rules also show where git said the work landed: a burn-like branch (a replay artifact), the default branch, another branch, or unknown.', '');
for (const k of kinds) {
  const s = tally.get(k);
  if (!s.deny) continue;
  md.push(`### ${k}`, '', '| Rule | Refused | Landed |', '|---|---|---|');
  for (const [rule, v] of [...s.rules.entries()].sort((a, b) => b[1].n - a[1].n)) {
    const landed = Object.entries(v.landed).sort((a, b) => b[1] - a[1]).map(([w, n]) => `${w} ${n}`).join(', ');
    md.push(`| ${rule} | ${v.n} | ${landed} |`);
  }
  md.push('');
}

const live = kinds.filter((k) => { const a = tally.get(k).agree; return a.both + a.liveOnly > 0; });
if (live.length) {
  md.push('## Against the live guard', '', 'Calls the guard refused when the session ran (its refusal is in the tool result), compared with the replay.', '');
  md.push('| Kind | Both refused | Live only | Replay only |', '|---|---|---|---|');
  for (const k of live) {
    const a = tally.get(k).agree;
    md.push(`| ${k} | ${a.both} | ${a.liveOnly} | ${a.replayOnly} |`);
  }
  md.push('');
}

md.push(`## Guard time per call during a run (${opts.jobs} at once, so this overstates one call on its own)`, '');
md.push('| Tool | Calls | p50 ms | p95 ms | Max ms |', '|---|---|---|---|---|');
for (const [g, arr] of [...latency.entries()].sort()) {
  md.push(`| ${g} | ${arr.length} | ${Math.round(q(arr, 0.5))} | ${Math.round(q(arr, 0.95))} | ${Math.round(Math.max(...arr))} |`);
}
md.push('');

writeFileSync(join(out, 'summary.md'), md.join('\n'));
process.stdout.write(md.join('\n') + '\n');
process.stderr.write(`replay: results in ${out}\n`);
