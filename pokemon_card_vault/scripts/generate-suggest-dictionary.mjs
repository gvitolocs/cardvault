// Local build tool only. Run with a read-only checkout of gvitolocs/pokoin.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

const SOURCE_COMMIT = 'd6c3ce2cb633d73c2474394ae3f12db50529014a';
const app = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2] && path.resolve(process.argv[2]);
if (!source) throw new Error('Usage: node scripts/generate-suggest-dictionary.mjs <pokoin-checkout>');
const git = (...args) => execFileSync('git', ['-c', `safe.directory=${source.split(path.sep).join('/')}`, ...args],
  { cwd: source, encoding: 'utf8' }).trim();
if (git('rev-parse', 'HEAD') !== SOURCE_COMMIT) {
  throw new Error(`Expected upstream commit ${SOURCE_COMMIT}; update the pin deliberately before regeneration.`);
}
const handoff = 'docs/handoff/flutter-suggest-dictionary';
const inputs = [
  `${handoff}/pkd1.mjs`, `${handoff}/measure-dictionary.mjs`, `${handoff}/export-golden.mjs`,
  'market/src/compact-query.js', 'market/src/data/suggest-names.js',
  'market/src/data/suggest-sets.js', 'market/src/data/suggest-artists.js',
  'market/src/tcg-eras.js',
];
if (git('status', '--porcelain', '--', 'market/src', handoff, 'docs/handoff/compact-c1/fixtures')) {
  throw new Error('Upstream search inputs must be clean at the pinned commit.');
}
const assetDir = path.join(app, 'assets/suggest');
const packageDir = path.join(app, 'lib/rebuild/packages/pokoin_suggest');
const goldenDir = path.join(packageDir, 'test/golden');
const referenceDir = path.join(packageDir, 'test/reference');
for (const dir of [assetDir, goldenDir, referenceDir]) fs.mkdirSync(dir, { recursive: true });
const asset = path.join(assetDir, 'dictionary.pkd1');
const run = (script, args) => execFileSync(process.execPath,
  [path.join(source, handoff, script), ...args], { cwd: source, stdio: 'inherit' });
run('measure-dictionary.mjs', ['--write-pkd1', asset]);
run('export-golden.mjs', [source, goldenDir]);

const load = (relative) => import(pathToFileURL(path.join(source, relative)).href);
const { canonicalTuples, contentHash, decodePkd1 } = await load(`${handoff}/pkd1.mjs`);
const { compactQuery } = await load('market/src/compact-query.js');
const { TCG_ERA_CATALOG } = await load('market/src/tcg-eras.js');
const { setAliasPool } = await load('market/src/suggest-rank.js');
const aliasRows = setAliasPool();
const collator = new Intl.Collator();
const aliasOrder = aliasRows.map((_, i) => i).sort((a, b) => collator.compare(aliasRows[a].display, aliasRows[b].display));
const aliasRanks = new Array(aliasRows.length);
let aliasRank = 0;
aliasOrder.forEach((row, i) => {
  if (i > 0 && collator.compare(aliasRows[aliasOrder[i - 1]].display, aliasRows[row].display) !== 0) aliasRank = i;
  aliasRanks[row] = aliasRank;
});
const dartLiteral = (value) => {
  if (typeof value === 'string') return JSON.stringify(value).replaceAll('$', '\\$');
  if (Array.isArray(value)) return `[${value.map(dartLiteral).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.entries(value)
    .map(([key, entry]) => `${dartLiteral(key)}:${dartLiteral(entry)}`).join(',')}}`;
  return JSON.stringify(value);
};
fs.writeFileSync(path.join(packageDir, 'lib/src/tcg_eras.g.dart'),
  '// Generated from the pinned upstream tcg-eras.js; do not edit.\n' +
  `const tcgEraCatalog = <Map<String, Object>>${dartLiteral(TCG_ERA_CATALOG.map(
    ({ id, en = [], jp = [], cn = [], extras = [] }) => ({ id, en, jp, cn, extras })))};\n` +
  `const eraAliasCollationRanks = <int>${dartLiteral(aliasRanks)};\n`);
const data = {
  names: (await load('market/src/data/suggest-names.js')).default,
  sets: (await load('market/src/data/suggest-sets.js')).default,
  artists: (await load('market/src/data/suggest-artists.js')).default,
};
const bytes = fs.readFileSync(asset);
const decoded = decodePkd1(bytes);
const hash = contentHash(data).toString('hex');
if (decoded.hash !== hash) throw new Error('Generated header differs from the canonical catalog hash');
const reference = {
  hash,
  names: data.names.map((r, i) => [r.display, r.prior, compactQuery(r.display), decoded.names.collation[i]]),
  sets: data.sets.map((r, i) => [r.display, r.slug, r.prior, r.nationality || '', compactQuery(r.display), decoded.sets.collation[i]]),
  artists: data.artists.map((r, i) => [r.display, r.slug, r.prior, compactQuery(r.display), decoded.artists.collation[i]]),
};
const writeJson = (file, value) => fs.writeFileSync(file, `${JSON.stringify(value)}\n`);
fs.writeFileSync(path.join(referenceDir, 'catalog.json.gz'),
  gzipSync(Buffer.from(`${JSON.stringify(reference)}\n`), { level: 9 }));
const metadata = JSON.parse(fs.readFileSync(path.join(goldenDir, 'meta.json'), 'utf8'));
metadata.sourceRepository = 'https://github.com/gvitolocs/pokoin';
metadata.sourceCommit = SOURCE_COMMIT;
metadata.contentHash = hash;
writeJson(path.join(goldenDir, 'meta.json'), metadata);
const sha256 = (b) => createHash('sha256').update(b).digest('hex');
const manifest = {
  sourceRepository: metadata.sourceRepository,
  sourceCommit: SOURCE_COMMIT,
  generator: `${handoff}/measure-dictionary.mjs`,
  formatVersion: 1,
  contentHash: hash,
  fileSha256: sha256(bytes),
  byteLength: bytes.length,
  counts: { names: data.names.length, sets: data.sets.length, artists: data.artists.length },
  node: process.version, icu: process.versions.icu, unicode: process.versions.unicode,
  canonicalTupleSha256: sha256(JSON.stringify(canonicalTuples(data))),
  inputs: Object.fromEntries(inputs.map((file) => [file, sha256(fs.readFileSync(path.join(source, file)))])),
};
writeJson(path.join(assetDir, 'manifest.json'), manifest);
fs.writeFileSync(path.join(packageDir, 'lib/src/bundled_dictionary.dart'),
  '// Generated by scripts/generate-suggest-dictionary.mjs.\n' +
  `const bundledDictionaryContentHash = '${hash}';\n` +
  `const bundledDictionarySourceCommit =\n    '${SOURCE_COMMIT}';\n`);
console.log(`Pinned dictionary: ${hash}; ${bytes.length} bytes; reference rows: ${data.names.length + data.sets.length + data.artists.length}`);
