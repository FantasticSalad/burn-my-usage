import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const scanner=fileURLToPath(new URL('./release-scan.mjs',import.meta.url));
function fixture(fn){
  const dir=mkdtempSync(join(tmpdir(),'release-check-'));
  const git=(...args)=>{const r=spawnSync('git',['-c','user.name=Fixture','-c','user.email=fixture@example.com',...args],{cwd:dir,encoding:'utf8'});assert.equal(r.status,0,r.stderr);};
  try {git('init','-q');fn(dir,git);}finally{rmSync(dir,{recursive:true,force:true});}
}
function scan(dir,...args){return spawnSync(process.execPath,[scanner,'--index',...args],{cwd:dir,encoding:'utf8'});}
test('ordinary staged file is clear',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'source.txt'),'ordinary source\n');git('add','source.txt');
  const r=scan(dir);assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/"findings":0/);
}));
test('synthetic token is blocked without being printed',()=>fixture((dir,git)=>{
  const fake=['ghp_', 'A'.repeat(32)].join('');
  writeFileSync(join(dir,'source.txt'),fake+'\n');git('add','source.txt');
  const r=scan(dir);assert.equal(r.status,1);assert.match(r.stdout,/possible secret/);assert.ok(!r.stdout.includes(fake));
}));
test('private term input is explicit and location-only',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'source.txt'),'fixture-private-label\n');git('add','source.txt');
  writeFileSync(join(dir,'filter.txt'),'fixture-private-label\n');
  const r=scan(dir,'--redaction-list',join(dir,'filter.txt'));assert.equal(r.status,1);assert.match(r.stdout,/private redaction term/);assert.ok(!r.stdout.includes('fixture-private-label'));
}));

function scanHistory(dir,...args){return spawnSync(process.execPath,[scanner,'--history',...args],{cwd:dir,encoding:'utf8'});}
test('history scans old subjects even when the latest subject is clear',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'source.txt'),'ordinary source\n');git('add','source.txt');
  const marker=['Machine','B'].join(' ');
  git('commit','-q','-m','Landing on '+marker);git('commit','-q','--allow-empty','-m','Generic follow-up');
  const r=scanHistory(dir);assert.equal(r.status,1,r.stderr);assert.match(r.stdout,/COMMIT_MESSAGE:1: personal marker/);assert.match(r.stdout,/"messages":2/);assert.ok(!r.stdout.includes(marker));
}));
test('commit body tokens are blocked without printing their values',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'source.txt'),'ordinary source\n');git('add','source.txt');
  const fake=['ghp_', 'B'.repeat(32)].join('');
  git('commit','-q','-m','Generic subject','-m',fake);
  const r=scanHistory(dir);assert.equal(r.status,1,r.stderr);assert.match(r.stdout,/COMMIT_MESSAGE:3: possible secret/);assert.ok(!r.stdout.includes(fake));
}));
test('private terms in messages are checked while author credits remain allowed',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'source.txt'),'ordinary source\n');git('add','source.txt');
  const author=['Ja','mes',' ','Bul','len'].join('');
  git('-c','user.name='+author,'commit','-q','-m','fixture-sensitive-label');
  writeFileSync(join(dir,'filter.txt'),'fixture-sensitive-label\n');
  const r=scanHistory(dir,'--redaction-list',join(dir,'filter.txt'));assert.equal(r.status,1,r.stderr);assert.match(r.stdout,/COMMIT_MESSAGE:1: private redaction term/);assert.ok(!r.stdout.includes('fixture-sensitive-label'));
}));
test('generic snapshot message and public author credit pass',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'source.txt'),'ordinary source\n');git('add','source.txt');
  const author=['Ja','mes',' ','Bul','len'].join('');
  git('-c','user.name='+author,'commit','-q','-m','Prepare release snapshot');
  const r=scanHistory(dir);assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/"messages":1/);assert.match(r.stdout,/"findings":0/);
}));

test('malformed manifest fails without echoing its synthetic token',()=>fixture((dir,git)=>{
  const fake=['ghp_','C'.repeat(32)].join('');
  const manifestDir=join(dir,'.claude-plugin');
  writeFileSync(join(dir,'plugin.txt'),'ordinary source\n');
  git('add','plugin.txt');
  // mkdir through the fixture filesystem, never a user configuration directory.
  mkdirSync(manifestDir);
  writeFileSync(join(manifestDir,'plugin.json'),'{"description":"'+fake+'","bad":}');
  git('add','.claude-plugin/plugin.json');
  const r=scan(dir);assert.equal(r.status,1,r.stderr);assert.match(r.stdout,/invalid manifest JSON/);assert.ok(!(r.stdout+r.stderr).includes(fake));
}));
test('unexpected binary content fails packaging',()=>fixture((dir,git)=>{
  writeFileSync(join(dir,'data.dat'),Buffer.from([0,1,2,3]));git('add','data.dat');
  const r=scan(dir);assert.equal(r.status,1,r.stderr);assert.match(r.stdout,/binary content/);
}));
