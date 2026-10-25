const plans = new Set(['beginner', 'week2', 'week3', 'week4', 'week5', 'week6', 'week7', 'week8', 'week9', 'freeRun', 'threeK', 'fiveK']);
export function validSummary(b) {
  if (!b || Array.isArray(b) || Object.keys(b).sort().join(',') !== 'completed,distance_m,duration_s,effort,plan,splits_s') return false;
  return plans.has(b.plan) && ['easy','right','hard','unspecified'].includes(b.effort)
    && typeof b.completed === 'boolean'
    && Number.isFinite(b.distance_m) && b.distance_m >= 0 && b.distance_m <= 100000
    && Number.isFinite(b.duration_s) && b.duration_s >= 0 && b.duration_s <= 86400
    && Array.isArray(b.splits_s) && b.splits_s.length <= 100
    && b.splits_s.every(x => Number.isFinite(x) && x > 0 && x <= 10000);
}
function reply(status, body) {
  return Response.json(body, {status, headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
}
async function authorized(request, expected) {
  if (!expected || expected.length < 24) return false;
  const hash = async text => new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)));
  const [a,b] = await Promise.all([hash(request.headers.get('Authorization') || ''),hash('Bearer ' + expected)]);
  let difference = 0;
  for (let i=0;i<a.length;i++) difference |= a[i] ^ b[i];
  return difference === 0;
}
export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (!await authorized(request, env.SERVICE_ACCESS_TOKEN)) return reply(401,{error:'Invalid access token'});
    if (path === '/health' && request.method === 'GET') return reply(200,{ok:true,ai_configured:!!env.AI_API_KEY && !!env.AI_MODEL});
    if (path !== '/v1/analysis' || request.method !== 'POST') return reply(404,{error:'Not found'});
    if (!request.headers.get('Content-Type')?.startsWith('application/json')) return reply(415,{error:'Expected JSON'});
    if (Number(request.headers.get('Content-Length')) > 16384) return reply(413,{error:'Body too large'});
    let body;
    try {
      const text = await request.text();
      if (text.length > 16384) return reply(413,{error:'Body too large'});
      body = JSON.parse(text);
    } catch { return reply(422,{error:'Invalid JSON'}); }
    if (!validSummary(body)) return reply(422,{error:'Expected aggregate metrics only; no GPS coordinates'});
    if (!env.AI_API_KEY || !env.AI_MODEL) return reply(503,{error:'AI not configured'});
    const base = env.AI_BASE_URL || 'https://api.deepseek.com';
    let url;
    try { url = new URL(base); } catch { return reply(503,{error:'Invalid provider config'}); }
    if (url.protocol !== 'https:' || !['api.deepseek.com','open.bigmodel.cn'].includes(url.hostname) || url.username || url.password || url.search || url.hash) return reply(503,{error:'Unsupported provider endpoint'});
    const payload = {
      model:env.AI_MODEL, stream:false, max_tokens:450,
      messages:[{role:'system',content:'你是中文跑步记录解读助手。只根据提供的主要训练统计和体感，用不超过180个汉字给出复盘和一条可操作建议。beginner和week2到week9是按时间执行的新手走跑训练，计划内步行不是掉速失败。freeRun是无固定距离的自由跑。completed=false是提前结束，不能说完成了预设目标。没有心率、坡度和伤病数据，不编造这些信息，不作诊断，不要求疲劳时加速。只输出纯文本。'},
        {role:'user',content:JSON.stringify(body)}]
    };
    if (['enabled','disabled'].includes(env.AI_THINKING)) payload.thinking = {type:env.AI_THINKING};
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25000);
    try {
      const upstream = await fetch(base.replace(/\/$/,'') + '/chat/completions',{
        method:'POST',headers:{'Authorization':'Bearer ' + env.AI_API_KEY,'Content-Type':'application/json'},
        body:JSON.stringify(payload),signal:controller.signal,redirect:'manual'
      });
      if (!upstream.ok) return reply(upstream.status===429 ? 429 : 502,{error:'Provider request failed; not retried'});
      const value = await upstream.json();
      const analysis = value?.choices?.[0]?.message?.content;
      if (typeof analysis !== 'string' || !analysis.trim()) return reply(502,{error:'Empty provider response'});
      return reply(200,{analysis:analysis.trim().slice(0,1500)});
    } catch (error) { return reply(504,{error:'Provider connection failed; not retried',category:error?.name || 'UnknownError'}); }
    finally { clearTimeout(timeout); }
  }
};
