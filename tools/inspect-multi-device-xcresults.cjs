const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

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

function inspectXcresult(xcresultDataDir) {
  const parsed = [];
  for (const name of fs.readdirSync(xcresultDataDir)) {
    if (!name.startsWith('data.')) continue;
    let b = fs.readFileSync(path.join(xcresultDataDir, name));
    if (b.subarray(0,4).toString('hex') === '28b52ffd') b = zlib.zstdDecompressSync(b);
    try {
      parsed.push({
        name,
        data: (b.subarray(0,2).toString()==='[T' || b.subarray(0,2).toString()==='[S')
          ? decodeXCObject(b)
          : unwrap(JSON.parse(b.toString('utf8')))
      });
    } catch {}
  }
  const root = parsed.find(x => Array.isArray(x.data?.actions) && x.data.metrics);
  if (!root) return null;

  const tests = [];
  function visit(x) {
    if (!x || typeof x !== 'object') return;
    if (x.testStatus) tests.push({ name: x.identifier || x.name, status: x.testStatus, duration: x.duration });
    for (const v of Object.values(x)) if (v && typeof v === 'object') visit(v);
  }
  parsed.forEach(x => visit(x.data));
  const uniqueTests = [...new Map(tests.map(x => [x.name, x])).values()];

  return {
    metrics: root.data.metrics,
    actions: root.data.actions.map(x => ({
      status: x.actionResult?.status,
      buildStatus: x.buildResult?.status,
      startedTime: x.startedTime,
      endedTime: x.endedTime,
      runDestination: x.runDestination
    })),
    tests: uniqueTests,
    decodedObjects: parsed.length
  };
}

const testResultsBase = path.resolve('ios/build/test_results');
const allResults = {};

for (const dir of fs.readdirSync(testResultsBase)) {
  const fullPath = path.join(testResultsBase, dir, 'UITests.xcresult', 'Data');
  if (fs.existsSync(fullPath)) {
    console.log(`Inspecting ${dir}...`);
    const res = inspectXcresult(fullPath);
    if (res) {
      const dest = res.actions[0]?.runDestination;
      const deviceName = dest?.displayName || dir;
      const targetArch = dest?.targetArchitecture || '';
      const osVersion = dest?.targetDeviceRecord?.operatingSystemVersion || '';
      const totalTests = res.tests.length;
      const failedTests = res.tests.filter(t => t.status !== 'Success');

      console.log(`- Device: ${deviceName} (OS: ${osVersion}, Arch: ${targetArch})`);
      console.log(`- Total Tests Executed: ${totalTests}, Passed: ${totalTests - failedTests.length}, Failed: ${failedTests.length}`);
      if (failedTests.length > 0) {
        console.log(`  Failed test names:`, failedTests.map(t => t.name));
      }

      allResults[dir] = {
        device: deviceName,
        osVersion,
        targetArch,
        totalTests,
        passedCount: totalTests - failedTests.length,
        failedCount: failedTests.length,
        tests: res.tests
      };
    }
  }
}

const outDir = path.resolve('docs/ios-parity-2.0.40/review-evidence/visual-matrix');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'multi-device-test-report.json'), JSON.stringify(allResults, null, 2));
console.log(`\nWritten multi-device-test-report.json successfully!`);
