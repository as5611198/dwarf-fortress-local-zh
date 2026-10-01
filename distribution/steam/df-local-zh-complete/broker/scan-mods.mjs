import { readdir, readFile, writeFile } from 'node:fs/promises';
import { resolve, join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { scanRawText } from './data.mjs';

const [output, ...roots] = process.argv.slice(2);
if (!output || !roots.length) throw new Error('Usage: node scan-mods.mjs <inventory.jsonl> <mod-root> ...');
const rows = [];
async function scan(path, owner, base) {
  for (const item of await readdir(path, { withFileTypes: true })) {
    const full = join(path, item.name);
    if (item.isDirectory()) await scan(full, owner, base);
    else if (item.isFile() && item.name.endsWith('.txt') && full.split(/[\\/]/).includes('objects')) {
      const content = await readFile(full, 'utf8');
      const sourceHash = createHash('sha256').update(content).digest('hex');
      rows.push(...scanRawText(content, owner, relative(base, full)).map(row => ({ ...row, sourceHash })));
    }
  }
}
for (const root of roots.map(root => resolve(root))) {
  for (const item of await readdir(root, { withFileTypes: true })) {
    if (!item.isDirectory()) continue;
    const base = join(root, item.name);
    let info;
    try { info = await readFile(join(base, 'info.txt'), 'utf8'); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    const id = info.match(/\[ID:([^\]]+)\]/)?.[1] ?? item.name;
    await scan(base, id, base);
  }
}
await writeFile(resolve(output), rows.map(row => JSON.stringify(row)).join('\n') + '\n', 'utf8');
console.log(JSON.stringify({ entries: rows.length, uniqueSources: new Set(rows.map(row => row.text)).size,
  mods: [...new Set(rows.map(row => row.mod))], output: resolve(output) }));
