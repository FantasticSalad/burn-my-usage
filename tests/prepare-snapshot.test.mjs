import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,copyFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=dirname(fileURLToPath(import.meta.url));
const preparer=join(here,'prepare-snapshot.mjs');
function fixture(fn){
  const directory=mkdtempSync(join(tmpdir(),'snapshot-check-'));
  const repo=join(directory,'source');mkdirSync(repo);
  const git=(...args)=>{const result=spawnSync('git',['-c','user.name=Fixture','-c','user.email=fixture@example.com','-c','core.autocrlf=false','-C',repo,...args],{encoding:'utf8'});assert.equal(result.status,0,result.stderr);return result.stdout.trim();};
  try{
    git('init','-q');mkdirSync(join(repo,'.claude-plugin'));mkdirSync(join(repo,'tests'));
    writeFileSync(join(repo,'.claude-plugin/plugin.json'),JSON.stringify({name:'burn-my-usage',version:'1.2.3'}));
    writeFileSync(join(repo,'source.txt'),'ordinary source\n');
    copyFileSync(join(here,'release-scan.mjs'),join(repo,'tests/release-scan.mjs'));
    git('add','.claude-plugin/plugin.json','source.txt','tests/release-scan.mjs');
    git('commit','-q','-m','Private landing on '+['Machine','B'].join(' '));
    fn(directory,repo,git);
  }finally{rmSync(directory,{recursive:true,force:true});}
}
const prepare=(repo,output)=>spawnSync(process.execPath,[preparer,output],{cwd:repo,encoding:'utf8'});
test('bundle replaces private metadata with one commit while preserving the exact tree',()=>fixture((directory,repo,git)=>{
  const oldTip=git('rev-parse','HEAD');
  const output=join(directory,'release');const result=prepare(repo,output);
  assert.equal(result.status,0,result.stderr);
  const manifest=JSON.parse(readFileSync(join(output,'snapshot.json'),'utf8'));
  assert.equal(manifest.commits,1);assert.equal(manifest.scan.messages,1);assert.equal(manifest.scan.findings,0);
  assert.equal(manifest.tree,git('rev-parse','HEAD^{tree}'));assert.equal(manifest.sourceCommit,oldTip);
  assert.notEqual(manifest.snapshotCommit,oldTip);assert.equal(git('rev-parse','HEAD'),oldTip);
  assert.equal(manifest.publicationAuthorized,false);assert.ok(existsSync(join(output,'burn-my-usage-1.2.3.bundle')));
}));
test('dirty source is refused before creating artifacts',()=>fixture((directory,repo)=>{
  writeFileSync(join(repo,'source.txt'),'uncommitted work\n');const output=join(directory,'release');
  const result=prepare(repo,output);assert.equal(result.status,2);assert.match(result.stderr,/commit source changes/);assert.equal(existsSync(output),false);
}));
test('existing artifact directories are preserved',()=>fixture((directory,repo)=>{
  const output=join(directory,'release');mkdirSync(output);writeFileSync(join(output,'keep.txt'),'preserve me');
  const result=prepare(repo,output);assert.equal(result.status,2);assert.equal(readFileSync(join(output,'keep.txt'),'utf8'),'preserve me');
}));
