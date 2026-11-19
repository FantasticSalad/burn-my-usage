#!/usr/bin/env node
// Explicit, model-free native probe. Never part of the synthetic test glob.
// Defaults to a new unauthenticated profile. --existing-profile temporarily registers
// uniquely named fixtures there; neither mode trusts hooks or starts a model.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { inspectNative } from '../scripts/codex-native-check.mjs';

const executable = process.env.BMU_CODEX_BIN;
if (!executable || !path.isAbsolute(executable)) throw Error('BMU_CODEX_BIN must be an absolute native executable');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bmu-native-discovery-'));
const home = path.join(root, 'synthetic-codex-home');
const existingProfile = process.argv.includes('--existing-profile');
const marketplace = `bmu-discovery-fixture-${path.basename(root).slice(-6).toLowerCase()}`;
fs.mkdirSync(home);
const json = (file, value) => {
  fs.mkdirSync(path.dirname(file), {recursive:true});
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n', {flag:'wx'});
};
const hooks = {hooks:{
  SessionStart:[{hooks:[{type:'command',command:'node -e "console.log(JSON.stringify({}))"'}]}],
  PreToolUse:[{hooks:[{type:'command',command:'node -e "console.log(JSON.stringify({}))"'}]}]
}};
const variants = [
  ['inline-path', {extensions:{'com.openai':{hooks:'./hooks/codex.json'}}}, null, 'hooks/codex.json'],
  ['default-file', {}, null, 'hooks/hooks.json'],
  ['compat-path', {}, {hooks:'./hooks/codex.json'}, 'hooks/codex.json'],
  ['legacy-only', null, {hooks:'./hooks/codex.json',skills:'./skills/'}, 'hooks/codex.json'],
  ['inline-object', {extensions:{'com.openai':{hooks}}}, null, null],
  ['inline-array', {extensions:{'com.openai':{hooks:['./hooks/codex.json']}}}, null, 'hooks/codex.json'],
  ['product-hooks', {}, {hooks:'./hooks/codex.json'}, 'hooks/codex.json'],
  ['burn-my-usage', {}, {hooks:'./hooks/codex.json'}, 'hooks/codex.json'],
  ['schema-compat', {$schema:'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'}, {hooks:'./hooks/codex.json'}, 'hooks/codex.json'],
  ['schema-default', {$schema:'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'}, null, 'hooks/hooks.json'],
  ['schema-inline', {$schema:'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json',extensions:{'com.openai':{hooks:'./hooks/codex.json'}}}, null, 'hooks/codex.json'],
  ['identity-no-schema', {author:{name:'Fixture Author'},license:'MIT'}, {hooks:'./hooks/codex.json'}, 'hooks/codex.json'],
];
for (const [name, portable, legacy, hookFile] of variants) {
  const dir = path.join(root, name);
  const identity = name === 'burn-my-usage' ? {...JSON.parse(fs.readFileSync(new URL('../plugin.json', import.meta.url), 'utf8')),name} : {name,version:'0.0.0',description:'Synthetic native discovery fixture'};
  if (portable) json(path.join(dir, 'plugin.json'), {...identity,...portable});
  if (legacy) json(path.join(dir, '.codex-plugin/plugin.json'), {...identity,...legacy});
  const product = ['product-hooks','burn-my-usage'].includes(name);
  if (hookFile) json(path.join(dir, hookFile), product ? JSON.parse(fs.readFileSync(new URL('../hooks/codex.json',import.meta.url),'utf8')) : hooks);
  const skill = path.join(dir, 'skills/burn-my-usage');
  fs.mkdirSync(skill, {recursive:true});
  fs.writeFileSync(path.join(skill, 'SKILL.md'), '---\nname: burn-my-usage\ndescription: Synthetic discovery fixture, never invoke.\n---\n\nDo not start any task.\n', {flag:'wx'});
}
json(path.join(root, '.agents/plugins/marketplace.json'), {name:marketplace,plugins:variants.map(([name]) => ({name,source:{source:'local',path:`./${name}`},policy:{installation:'AVAILABLE',authentication:'ON_INSTALL'},category:'Productivity'}))});
const env = existingProfile ? {...process.env} : {...process.env,CODEX_HOME:home};
const run = args => {
  const result = spawnSync(executable, args, {env,cwd:root,encoding:'utf8',timeout:20000,maxBuffer:1048576,windowsHide:true});
  if (result.status !== 0) throw Error(`native fixture command failed: ${args.slice(0,2).join(' ')}`);
  return result.stdout;
};
const priorHome = process.env.CODEX_HOME;
const installed = [];
let added = false;
const discoveredVariants = new Set(['default-file','compat-path','legacy-only','product-hooks','identity-no-schema']);
try {
  console.log(JSON.stringify({client:run(['--version']).trim(),modelCalls:0,profile:existingProfile?'existing-only-fixture-plugin-registration':'new-unauthenticated'}));
  run(['plugin','marketplace','add',root,'--json']);
  added = true;
  if (!existingProfile) process.env.CODEX_HOME = home;
  for (const [name] of variants) {
    run(['plugin','add',`${name}@${marketplace}`,'--json']);
    installed.push(name);
    const result = await inspectNative(root,`${name}@${marketplace}`);
    console.log(JSON.stringify({variant:name,...result}));
    if (!result.skillDiscovered || result.events.some(e => e.discovered !== discoveredVariants.has(name)) ||
        result.events.some(e => e.enabledAndTrusted)) throw Error(`unexpected native fixture result: ${name}`);
  }
} finally {
  let cleanupFailed = false;
  if (existingProfile) {
    for (const name of installed) {
      try { run(['plugin','remove',`${name}@${marketplace}`]); } catch { cleanupFailed = true; }
    }
    if (added && !cleanupFailed) {
      try { run(['plugin','marketplace','remove',marketplace]); } catch { cleanupFailed = true; }
    }
  }
  if (priorHome === undefined) delete process.env.CODEX_HOME;
  else process.env.CODEX_HOME = priorHome;
  if (cleanupFailed) throw Error(`fixture registration cleanup failed; preserve source at ${root}`);
  // Delete only this mkdtemp fixture after canonical containment validation.
  const canonical = fs.realpathSync(root), temp = fs.realpathSync(os.tmpdir());
  const relative = path.relative(temp, canonical);
  if (!relative.startsWith('..') && !path.isAbsolute(relative) && /^bmu-native-discovery-[^\\/]+$/.test(relative)) {
    fs.rmSync(canonical, {recursive:true,force:true});
  } else throw Error('native fixture cleanup containment check failed');
}
