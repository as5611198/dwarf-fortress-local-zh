import { createHash } from 'node:crypto';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const packageRoot = resolve(process.argv[2] ?? resolve(fileURLToPath(import.meta.url), '../../workshop/df-local-zh-complete'));
const allowUnverifiedUpstream = process.argv.includes('--allow-unverified-upstream');
const manifestPath = join(packageRoot, 'PACKAGE-MANIFEST.json');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const adapterOnly = manifest.releaseMode === 'adapter-only';
const upstreamDataBundled = manifest.upstreamDataBundled !== false;
const errors = [];
const expected = new Map(manifest.files.map(entry => [entry.path, entry.sha256]));
const binaryExtensions = new Set(['.dll', '.exe', '.node', '.otf', '.png', '.so']);

async function walk(dir) {
  const files = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...await walk(path));
    else files.push(path);
  }
  return files;
}

const files = await walk(packageRoot);
const actual = new Map();
for (const path of files) {
  const rel = relative(packageRoot, path).replaceAll('\\', '/');
  if (rel === 'PACKAGE-MANIFEST.json') continue;
  const digest = createHash('sha256').update(await readFile(path)).digest('hex');
  actual.set(rel, digest);
  if (expected.get(rel) !== digest) errors.push(`manifest mismatch: ${rel}`);
  if (!expected.has(rel)) errors.push(`unlisted file: ${rel}`);
  if (binaryExtensions.has(rel.slice(rel.lastIndexOf('.')).toLowerCase())) continue;
  const content = await readFile(path, 'utf8');
  if (/[A-Z]:[\\/]+Users[\\/]/i.test(content)) errors.push(`absolute user path: ${rel}`);
  const textData = /\.(?:json|csv|toml|txt)$/i.test(rel) && !rel.startsWith('broker/node_modules/');
  if (textData && /(?:api[_ -]?key|world-names\.json|translations\.jsonl|server\.(?:stdout|stderr)\.log|\.codex)/i.test(content)) {
    errors.push(`private runtime value: ${rel}`);
  }
}
for (const rel of expected.keys()) if (!actual.has(rel)) errors.push(`missing manifest file: ${rel}`);

const info = await readFile(join(packageRoot, 'info.txt'), 'utf8');
for (const field of ['[ID:df-local-zh-complete]', '[STEAM_TITLE:', '[STEAM_DESCRIPTION:', '[STEAM_TAG:dfhack]']) {
  if (!info.includes(field)) errors.push(`missing info metadata: ${field}`);
}
if (info.includes('[STEAM_FILE_ID:')) errors.push('new package must not carry STEAM_FILE_ID');
const requiredPaths = ['README.md', 'WORKSHOP-PUBLISHING.md', 'preview.png', 'scripts_modinstalled', 'broker'];
if (upstreamDataBundled) requiredPaths.push('dfi18n-data');
for (const requiredPath of requiredPaths) {
  try { await stat(join(packageRoot, requiredPath)); }
  catch { errors.push(`missing required path: ${requiredPath}`); }
}
if (adapterOnly && upstreamDataBundled) errors.push('adapter-only package incorrectly bundles upstream data');
if (adapterOnly) {
  try { await stat(join(packageRoot, 'dfi18n-data')); errors.push('adapter-only package contains dfi18n-data'); }
  catch { /* expected: upstream data is supplied by the subscribed dependency */ }
}
if (!manifest.privateRuntimeExcluded) errors.push('manifest does not confirm private runtime exclusion');
try { await stat(join(packageRoot, 'broker', 'node_modules', 'fast-xml-parser')); }
catch { errors.push('missing bundled broker dependency: fast-xml-parser'); }
try { await stat(join(packageRoot, 'broker', 'node_modules', 'opencc-js')); }
catch { errors.push('missing bundled broker dependency: opencc-js'); }
if (upstreamDataBundled && manifest.upstreamRedistributionApproved !== true && !allowUnverifiedUpstream) {
  errors.push('upstream redistribution is not approved (use --allow-unverified-upstream for a private test package)');
}

if (errors.length) {
  console.error(errors.map(error => `- ${error}`).join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Workshop package valid: ${manifest.package} ${manifest.version} (${actual.size} files)`);
}
