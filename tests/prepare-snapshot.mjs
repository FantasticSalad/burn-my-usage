// Prepare an unpublished, parentless release bundle without rewriting the source repo.
// node tests/prepare-snapshot.mjs <new-output-directory>
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,join,dirname,basename,sep} from 'node:path';
import {createHash} from 'node:crypto';
function run(command,args,cwd,env){
  const result=spawnSync(command,args,{cwd,env,encoding:'utf8',maxBuffer:32*1024*1024});
  if(result.status!==0)throw new Error(`${basename(command)} ${basename(args[0]||'operation')} failed (exit ${result.status})`);
  return result.stdout.trim();
}
const git=(cwd,...args)=>run('git',args,cwd);
let workspace;
try{
  if(process.argv.length!==3)throw new Error('usage: prepare-snapshot.mjs <new-output-directory>');
  const repo=realpathSync(git(process.cwd(),'rev-parse','--show-toplevel'));
  const requested=resolve(process.argv[2]);
  const output=join(realpathSync(dirname(requested)),basename(requested));
  const comparable=path=>process.platform==='win32'?path.toLowerCase():path;
  if(comparable(output)===comparable(repo)||comparable(output).startsWith(comparable(repo+sep)))throw new Error('output must be outside the repository');
  if(git(repo,'status','--porcelain'))throw new Error('commit source changes before preparing a snapshot');
  let manifest;
  try{manifest=JSON.parse(readFileSync(join(repo,'.claude-plugin/plugin.json'),'utf8'));}catch{throw new Error('invalid plugin manifest');}
  const version=manifest.version;
  if(!/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$/.test(version))throw new Error('invalid release version');
  const source=git(repo,'rev-parse','HEAD');
  const tree=git(repo,'rev-parse','HEAD^{tree}');
  // A fresh directory is mandatory. Never replace an existing artifact or adopt a repo.
  mkdirSync(output);
  workspace=mkdtempSync(join(realpathSync(tmpdir()),'release-snapshot-'));
  const bare=join(workspace,'objects.git');
  git(workspace,'init','--bare','--initial-branch=main',bare);
  git(bare,'fetch','--no-tags','--no-write-fetch-head','--no-auto-maintenance','--no-recurse-submodules',repo,source);
  const timestamp=git(repo,'show','-s','--format=%ct',source);
  if(!/^\d+$/.test(timestamp))throw new Error('invalid source timestamp');
  const snapshot=run('git',['-c','user.name=Release snapshot','-c','user.email=release@example.invalid','commit-tree',tree,'-m',`Prepare Burn My Usage ${version}`],bare,{...process.env,GIT_AUTHOR_DATE:`@${timestamp} +0000`,GIT_COMMITTER_DATE:`@${timestamp} +0000`});
  git(bare,'update-ref','refs/heads/main',snapshot);
  const bundle=join(output,`burn-my-usage-${version}.bundle`);
  git(bare,'bundle','create',bundle,'refs/heads/main');
  git(bare,'bundle','verify',bundle);
  const heads=git(bare,'bundle','list-heads',bundle).split(/\r?\n/);
  if(heads.length!==1||heads[0]!==snapshot+' refs/heads/main')throw new Error('unexpected bundle references');
  const imported=join(workspace,'verify.git');
  git(workspace,'clone','--bare','--branch','main',bundle,imported);
  if(git(imported,'rev-list','--all','--count')!=='1')throw new Error('snapshot includes additional history');
  if(git(imported,'rev-parse','HEAD^{tree}')!==tree)throw new Error('snapshot tree mismatch');
  git(imported,'fsck','--full','--no-reflogs');
  const scanText=run(process.execPath,[join(repo,'tests/release-scan.mjs'),'--history'],imported);
  const scan=JSON.parse(scanText.split(/\r?\n/).at(-1));
  if(scan.findings!==0||scan.revisions!==1||scan.messages!==1)throw new Error('snapshot audit is incomplete');
  const evidence={version,sourceCommit:source,tree,snapshotCommit:snapshot,commits:1,refs:['refs/heads/main'],bundleSha256:createHash('sha256').update(readFileSync(bundle)).digest('hex'),scan,publicationAuthorized:false};
  writeFileSync(join(output,'snapshot.json'),JSON.stringify(evidence,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(evidence));
}catch(error){
  console.error(error.code?`filesystem operation failed (${error.code})`:error.message);
  process.exitCode=2;
}finally{
  if(workspace){
    const parent=realpathSync(tmpdir());
    if(dirname(workspace)!==parent||!basename(workspace).startsWith('release-snapshot-'))throw new Error('refusing unexpected cleanup target');
    rmSync(workspace,{recursive:true,force:true});
  }
}
