// Summarise this synthetic fixture's exported result, never native session history.
import {readFileSync} from 'node:fs';
let result,skillCalls=0,bashCalls=0,toolCalls=0;
const assistantIds=new Set(),toolRoundIds=new Set(),toolResultIds=new Set();
for(const line of readFileSync(process.argv[2],'utf8').split(/\r?\n/)){
  if(!line.startsWith('{'))continue;
  let event;try{event=JSON.parse(line);}catch{continue;}
  if(event.type==='result')result=event;
  if(event.type==='assistant'&&event.message?.id)assistantIds.add(event.message.id);
  for(const content of event.message?.content||[]){
    if(content.type==='tool_result'&&content.tool_use_id)toolResultIds.add(content.tool_use_id);
    if(content.type!=='tool_use')continue;
    if(event.message?.id)toolRoundIds.add(event.message.id);
    toolCalls++;if(content.name==='Skill')skillCalls++;if(content.name==='Bash')bashCalls++;
  }
}
console.log(JSON.stringify({terminalResult:!!result,subtype:result?.subtype,isError:result?.is_error,reportedTurns:result?.num_turns,assistantRounds:assistantIds.size,toolUseRounds:toolRoundIds.size,toolResults:toolResultIds.size,skillCalls,bashCalls,toolCalls,estimatedCostUsd:result?.total_cost_usd}));
