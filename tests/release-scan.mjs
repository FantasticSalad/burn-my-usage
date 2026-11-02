// Location-only packaging/privacy audit. Node 18+, git; no model calls.
// node tests/release-scan.mjs [--history] [--redaction-list <user-supplied-file>]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const args = process.argv.slice(2);
const history = args.includes('--history');
const staged = args.includes('--index');
const index = args.indexOf('--redaction-list');
const terms = index < 0 ? [] : readFileSync(args[index + 1], 'utf8').split(/\r?\n/).map(x => x.trim()).filter(x => x && !x.startsWith('#'));
function git(...argv) {
  const p = spawnSync('git', argv, {encoding:'utf8', maxBuffer:32*1024*1024});
  if (p.status !== 0) throw new Error('git audit operation failed');
  return p.stdout;
}
const personal = [
  ['Ja','mes'].join(''), ['Bul','len'].join(''), ['auto','pilot'].join(''),
  ['C:',String.fromCharCode(92),'Code'].join(''), ['C:', '/', 'Code'].join(''),
  ['~/', 'One', 'Drive'].join(''), ['~/','se','crets'].join(''),
  ['session','.sh'].join(''), ['notice','board'].join('')
];
const secret = /(?:-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|(?:AKIA|ASIA)[A-Z0-9]{16}|xox[abprs]-[A-Za-z0-9-]{10,})/;
let failures=0, files=0, messages=0;
function scanText(ref,name,body){
  const fail=(line,kind)=>{console.log(ref.slice(0,8)+':'+name+':'+line+': '+kind);failures++;};
  body.split(/\r?\n/).forEach((line,i)=>{
    if(personal.some(x=>line.toLowerCase().includes(x.toLowerCase()))||/\bMachine [AB]\b|\b00_[A-Z_]+\.md\b/.test(line))fail(i+1,'personal marker');
    if(secret.test(line))fail(i+1,'possible secret');
    if(terms.some(x=>line.toLowerCase().includes(x.toLowerCase())))fail(i+1,'private redaction term');
  });
}
const refs = history ? git('rev-list','--all').trim().split(/\s+/).filter(Boolean) : [staged ? 'INDEX' : 'HEAD'];
for (const ref of refs) {
  if(!staged){
    // Author/license credits are allowed; subjects and bodies receive no exemptions.
    scanText(ref,'COMMIT_MESSAGE',git('show','-s','--format=%B',ref));
    messages++;
  }
  const rows=(staged ? git('ls-files','--stage','-z') : git('ls-tree','-rlz',ref)).split('\0').filter(Boolean);
  for (const row of rows) {
    const [meta,name] = row.split('\t');
    let [mode,type,sha,size]=meta.trim().split(/\s+/);
    if(staged){sha=type;type='blob';size=git('cat-file','-s',sha).trim();}
    const fail=(line,kind)=>{console.log(ref.slice(0,8)+':'+name+':'+line+': '+kind);failures++;};
    if (mode==='120000'||type==='commit'||Number(size)>262144||/(^|\/)(bin|node_modules|results)(\/|$)|(^|\/)(\.DS_Store|Thumbs\.db|desktop\.ini)$/.test(name)) { fail(0,'packaging'); continue; }
    // Never open a credential-shaped tracked file.
    if (/(^|\/)(\.env(?:$|\.)|token\.json$|credentials\.json$)/.test(name)) {fail(0,'forbidden file');continue;}
    if (/\.(png|jpe?g|gif|woff2?|ttf)$/i.test(name)) continue;
    files++;
    let body=git('cat-file','blob',sha);
    if(body.includes('\0')){fail(0,'binary content');continue;}
    if(name==='LICENSE')body=body.replace(/^Copyright.*$/m,'');
    if(name==='.claude-plugin/plugin.json'||name==='.claude-plugin/marketplace.json'){
      let m;try{m=JSON.parse(body);}catch{fail(0,'invalid manifest JSON');continue;}
      if(m.author)delete m.author.name;if(m.owner)delete m.owner.name;body=JSON.stringify(m,null,2);
    }
    scanText(ref,name,body);
  }
}
console.log(JSON.stringify({revisions:refs.length,files,messages,findings:failures,privateListSupplied:index>=0}));
process.exitCode=failures?1:0;
