import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const checker=join(dirname(fileURLToPath(import.meta.url)),'check-eval.mjs');
function sample(){return {partial:false,cases:[{runsPerCase:1,maxTurns:2,arms:{with:[{error:null,skippedPaidGraders:false,passed:true,turns:4,graders:[{passed:true}]}],without:[{error:null,skippedPaidGraders:false,passed:false,turns:4,graders:[{passed:false}]}]}}]};}
function check(change){const directory=mkdtempSync(join(tmpdir(),'eval-gate-'));try{const report=sample();change(report);const path=join(directory,'aggregate-result.json');writeFileSync(path,JSON.stringify(report));return spawnSync(process.execPath,[checker,path],{encoding:'utf8'});}finally{rmSync(directory,{recursive:true,force:true});}}
test('judged baseline failure is valid comparison evidence',()=>{const result=check(()=>{});assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/"baselinePassed":0/);});
test('baseline execution error fails even when the plugin passed and partial is false',()=>{const result=check(report=>report.cases[0].arms.without[0].error='synthetic private error text');assert.equal(result.status,1);assert.ok(!result.stdout.includes('synthetic private error text'));});
test('skipped paid graders fail the release gate',()=>{const result=check(report=>report.cases[0].arms.with[0].skippedPaidGraders=true);assert.equal(result.status,1);});
test('judged plugin failure fails the gate',()=>{const result=check(report=>report.cases[0].arms.with[0].passed=false);assert.equal(result.status,1);});
test('reported message counts are not compared to the tool-round budget',()=>{const result=check(report=>report.cases[0].arms.with[0].turns=13);assert.equal(result.status,0);});
test('missing baseline runs fail instead of passing an empty comparison',()=>{const result=check(report=>report.cases[0].arms.without=[]);assert.equal(result.status,1);});
