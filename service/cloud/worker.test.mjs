import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker,{validSummary} from './worker.mjs';
const summary={plan:'threeK',distance_m:1234,duration_s:850,splits_s:[660],effort:'right',completed:false};
const token='synthetic-test-token-never-a-real-secret';
test('all new plan IDs accepted; GPS and invalid numbers rejected',()=>{
  for (const plan of ['week2','week9','freeRun']) assert.equal(validSummary({...summary,plan}),true);
  for (const b of [{...summary,track:[]},{...summary,distance_m:NaN},{...summary,splits_s:[-1]},{...summary,plan:'unknown'}]) assert.equal(validSummary(b),false);
});
test('auth fails before any provider request',async()=>{
  const response=await worker.fetch(new Request('https://test.invalid/v1/analysis',{method:'POST',body:JSON.stringify(summary)}),{SERVICE_ACCESS_TOKEN:token});
  assert.equal(response.status,401);
});
test('authenticated health does not call provider',async()=>{
  const response=await worker.fetch(new Request('https://test.invalid/health',{headers:{Authorization:'Bearer '+token}}),{SERVICE_ACCESS_TOKEN:token,AI_MODEL:'fake',AI_API_KEY:'fake'});
  assert.equal(response.status,200);
  assert.equal((await response.json()).ai_configured,true);
});
test('provider response returned and errors not retried',async()=>{
  const saved=globalThis.fetch;
  let calls=0;
  globalThis.fetch=async(_url,options)=>{
    calls++;
    assert.deepEqual(JSON.parse(JSON.parse(options.body).messages[1].content),summary);
    return Response.json({choices:[{message:{content:'先保持舒服的节奏。'}}]});
  };
  try {
    const request=()=>new Request('https://test.invalid/v1/analysis',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(summary)});
    const env={SERVICE_ACCESS_TOKEN:token,AI_MODEL:'fake',AI_API_KEY:'fake'};
    const ok=await worker.fetch(request(),env);
    assert.equal((await ok.json()).analysis,'先保持舒服的节奏。');
    globalThis.fetch=async()=>{calls++;return new Response('',{status:429});};
    assert.equal((await worker.fetch(request(),env)).status,429);
    assert.equal(calls,2);
  } finally {globalThis.fetch=saved;}
});
