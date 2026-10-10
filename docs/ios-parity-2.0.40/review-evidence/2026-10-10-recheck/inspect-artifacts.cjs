const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const base = path.resolve('build_artifacts/tests/ui-results-ZPe9KM/UITests.xcresult/Data');
const output = path.resolve('ios/build/acceptance-recheck-2026-10-10');
function unwrap(x) {
  if (!x || typeof x !== 'object') return x;
  if ('_value' in x) return x._value;
  if ('_values' in x) return x._values.map(unwrap);
  if (Array.isArray(x)) return x.map(unwrap);
  return Object.fromEntries(Object.entries(x).filter(([k]) => k !== '_type').map(([k,v]) => [k,unwrap(v)]));
}
function decodeXCObject(b) {
  let at=0;
  function counted(tag) {
    if (String.fromCharCode(b[at++])!==tag) throw Error('Unexpected tag');
    const start=at;
    while(b[at]!==58) at++;
    const length=Number(b.subarray(start,at).toString());
    at++;
    const text=b.subarray(at,at+length).toString('utf8');
    at+=length;
    return text;
  }
  function value() {
    if (b[at]===86) return counted('V');
    if (b[at++]!==91) throw Error('Expected object');
    let type='';
    if(b[at]===84) { at++; type=value()._n; }
    else if(b[at]===83) type=counted('S');
    const fields={}; const entries=[];
    while(b[at]!==93 && at<b.length) {
      if(b[at]===75) {const key=counted('K');fields[key]=value();}
      else entries.push(value());
    }
    at++;
    if ('_v' in fields) return fields._v;
    if(type==='Array' || entries.length) return entries;
    return fields;
  }
  return value();
}
const parsed = [];
for (const name of fs.readdirSync(base)) {
  if (!name.startsWith('data.')) continue;
  let b = fs.readFileSync(path.join(base,name));
  if (b.subarray(0,4).toString('hex') === '28b52ffd') b = zlib.zstdDecompressSync(b);
  try { parsed.push({name, data: b.subarray(0,2).toString()==='[T' || b.subarray(0,2).toString()==='[S' ? decodeXCObject(b) : unwrap(JSON.parse(b.toString('utf8')))}); } catch {}
}
const root = parsed.find(x=>x.name.startsWith('data.0~hD_wzk6EL3gpKY5jwMVtovl_'));
if (!root) throw Error('xcresult root not found');
fs.writeFileSync(path.join(output,'xcresult-root.json'), JSON.stringify(root.data,null,2));
const tests=[];
function visit(x) {
  if (!x || typeof x !== 'object') return;
  if (x.testStatus) tests.push({name:x.identifier || x.name, status:x.testStatus, duration:x.duration});
  for (const v of Object.values(x)) if (v && typeof v==='object') visit(v);
}
parsed.forEach(x=>visit(x.data));
const uniqueTests=[...new Map(tests.map(x=>[x.name,x])).values()];
const summary={metrics:root.data.metrics, actions:root.data.actions.map(x=>({status:x.actionResult.status,metrics:x.actionResult.metrics,buildStatus:x.buildResult.status,startedTime:x.startedTime,endedTime:x.endedTime,runDestination:x.runDestination})), tests:uniqueTests, decodedObjects:parsed.length};
fs.writeFileSync(path.join(output,'artifact-inspection.json'),JSON.stringify(summary,null,2));
console.log(JSON.stringify(summary,null,2));
