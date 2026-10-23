process.loadEnvFile?.('.env');
const BASE = 'https://guistudy.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const id = process.argv[2] || '1sdc49P3eKm';
const res = await fetch(`${BASE}/tabs/${id}`, { headers: { 'User-Agent': UA } });
const html = await res.text();
const marker = '&quot;sheetInfo&quot;:[0,{';
const i = html.indexOf(marker);
let depth = 0, j = i + marker.length - 1;
for (; j < html.length; j++) { const c = html[j]; if (c === '{' || c === '[') depth++; else if (c === '}' || c === ']') { depth--; if (depth === 0) break; } }
const raw = html.slice(i, j + 1);
const un = raw.replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#x27;/g, "'");
console.log('=== region 840-1000 (unescaped) ===');
console.log(un.slice(840, 1000));
console.log('=== region 840-1000 (raw) ===');
console.log(raw.slice(840, 1000));