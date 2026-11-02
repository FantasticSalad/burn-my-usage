// Release gate for native aggregate-result.json exports. No model calls.
import {readFileSync} from 'node:fs';
import {basename} from 'node:path';
if(process.argv.length<3){console.error('usage: check-eval.mjs <aggregate-result.json> [...]');process.exit(2);}
let failures=0;
for(const [index,path] of process.argv.slice(2).entries()){
  const label=`report-${index+1}`;
  try{
    if(basename(path)!=='aggregate-result.json')throw new Error('expected native aggregate report filename');
    let report;
    try{report=JSON.parse(readFileSync(path,'utf8'));}catch{throw new Error('unreadable or invalid native report');}
    if(report.partial!==false||!Array.isArray(report.cases)||report.cases.length===0)throw new Error('incomplete report');
    let runs=0,pluginPassed=0,baselinePassed=0,errors=0;
    for(const [caseIndex,entry] of report.cases.entries()){
      if(!Number.isInteger(entry.runsPerCase)||entry.runsPerCase<1)throw new Error('missing expected run count');
      for(const arm of ['with','without']){
        const samples=entry.arms?.[arm];
        if(!Array.isArray(samples)||samples.length!==entry.runsPerCase)throw new Error('incomplete comparison arm');
        for(const [runIndex,run] of samples.entries()){
          runs++;
          const bad=run.error!==null||run.skippedPaidGraders!==false||typeof run.passed!=='boolean'||!Array.isArray(run.graders)||run.graders.length===0||run.graders.some(grader=>grader.error!=null);
          if(bad){console.log(`${label}:case-${caseIndex+1}:${arm}:run-${runIndex+1}: execution/grading error`);errors++;}
          if(run.passed===true){if(arm==='with')pluginPassed++;else baselinePassed++;}
          if(arm==='with'&&run.passed!==true){console.log(`${label}:case-${caseIndex+1}:${arm}:run-${runIndex+1}: plugin check failed`);errors++;}
        }
      }
    }
    console.log(JSON.stringify({report:label,runs,pluginPassed,baselinePassed,errors,partial:false}));
    if(errors)failures++;
  }catch(error){console.log(`${label}: ${error.message}`);failures++;}
}
process.exitCode=failures?1:0;
