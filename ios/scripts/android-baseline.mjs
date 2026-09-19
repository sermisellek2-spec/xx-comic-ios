import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const output = fileURLToPath(new URL('../android-baseline.json', import.meta.url));
const files = {};
async function scan(relative) {
  for (const entry of (await readdir(path.join(root, relative), { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name, 'en'))) {
    const name = `${relative}/${entry.name}`;
    if (entry.isDirectory()) await scan(name);
    else if (entry.isFile()) files[name] = createHash('sha256').update(await readFile(path.join(root, name))).digest('hex');
  }
}
await scan('app/src');
files['app/build.gradle'] = createHash('sha256').update(await readFile(path.join(root, 'app/build.gradle'))).digest('hex');
if (process.argv.includes('--check')) {
  const baseline = JSON.parse(await readFile(output, 'utf8'));
  const changed = [...new Set([...Object.keys(files), ...Object.keys(baseline.files)])].filter(name => files[name] !== baseline.files[name]);
  if (changed.length) {
    console.error(`Android 基准变化 (${changed.length}):\n${changed.join('\n')}`);
    process.exitCode = 1;
  } else console.log(`Android 基准一致：${Object.keys(files).length} 个文件`);
} else {
  const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  await writeFile(output, JSON.stringify({ version: '2.0.29', commit, files }, null, 2) + '\n');
  console.log(`已保存 ${Object.keys(files).length} 个 Android 文件的 SHA-256`);
}
