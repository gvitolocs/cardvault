const fs = require('fs');
const { execFileSync } = require('child_process');
const { Client } = require('pg');

const DEFAULT_OUTPUT = 'data/trainingai/best-blueprint-images.json';
const DEFAULT_BUCKET = 'cardvault-images';
const DEFAULT_R2_KEY = 'manifests/best-blueprint-images.json';
const DEFAULT_PUBLIC_BASE = 'https://trainingai.pokoin.com/images';

function parseArgs(argv) {
  const args = {
    envFile: '.env.local',
    output: DEFAULT_OUTPUT,
    publicBaseUrl: DEFAULT_PUBLIC_BASE,
    uploadR2: false,
    bucket: DEFAULT_BUCKET,
    r2Key: DEFAULT_R2_KEY,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const readValue = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`Missing value for ${arg}`);
      }
      return argv[index];
    };

    if (arg === '--env') args.envFile = readValue();
    else if (arg === '--output') args.output = readValue();
    else if (arg === '--public-base-url') args.publicBaseUrl = readValue().replace(/\/+$/, '');
    else if (arg === '--upload-r2') args.uploadR2 = true;
    else if (arg === '--bucket') args.bucket = readValue();
    else if (arg === '--r2-key') args.r2Key = readValue().replace(/^\/+/, '');
    else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

function printHelp() {
  console.log(`Usage: node scripts/generate-trainingai-best-blueprint-images.js [options]

Options:
  --env <path>              Env file with MARKETPLACE_DATABASE_URL and optional Cloudflare env.
  --output <path>           Output JSON path. Default: ${DEFAULT_OUTPUT}
  --public-base-url <url>   Public image base URL. Default: ${DEFAULT_PUBLIC_BASE}
  --upload-r2               Upload the generated JSON to Cloudflare R2 through wrangler.
  --bucket <name>           R2 bucket for --upload-r2. Default: ${DEFAULT_BUCKET}
  --r2-key <key>            R2 object key for --upload-r2. Default: ${DEFAULT_R2_KEY}
`);
}

function readEnv(path) {
  const values = {};
  if (!fs.existsSync(path)) {
    return { ...process.env };
  }
  for (const rawLine of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const index = line.indexOf('=');
    const key = line.slice(0, index).trim().replace(/^export\s+/, '');
    let value = line.slice(index + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return { ...values, ...process.env };
}

function normalizeCardTraderUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return `https://cardtrader.com${raw}`;
  return raw;
}

function encodeObjectKey(key) {
  return String(key).split('/').map(encodeURIComponent).join('/');
}

function defaultEditableProperty(editableProperties, name) {
  if (!Array.isArray(editableProperties)) {
    return '';
  }
  const expected = name.toLowerCase();
  const found = editableProperties.find((property) => String(property?.name || '').toLowerCase() === expected);
  return found ? String(found.default_value || '') : '';
}

function isUsableCdnKey(key) {
  const lower = String(key || '').toLowerCase();
  return Boolean(
    lower &&
    !lower.includes('_homepage') &&
    !lower.includes('-homepage') &&
    !lower.includes('/previews/') &&
    !lower.includes('preview_')
  );
}

function mapBlueprintRow(row, publicBaseUrl) {
  const objectKey = String(row.cdn_object_key || '').trim();
  const sourceUrl = normalizeCardTraderUrl(row.cardtrader_image_url || row.blueprint_image_url);

  let url = '';
  let source = '';
  let selectedObjectKey = '';
  if (isUsableCdnKey(objectKey)) {
    selectedObjectKey = objectKey;
    url = `${publicBaseUrl}/${encodeObjectKey(objectKey)}`;
    source = objectKey.toLowerCase().includes('full') ? 'r2_full' : 'r2_best';
  } else if (sourceUrl && !sourceUrl.toLowerCase().includes('/preview_')) {
    url = sourceUrl;
    source = 'cardtrader_source';
  } else {
    return null;
  }

  const editable = row.editable_properties || [];
  return {
    blueprint_id: String(row.blueprint_id),
    object_key: selectedObjectKey,
    original_path: selectedObjectKey || url,
    url,
    source,
    name: row.name || '',
    version: row.version || '',
    set_name: row.set_name || '',
    rarity: row.rarity || '',
    collector_number:
      defaultEditableProperty(editable, 'collector_number') ||
      defaultEditableProperty(editable, 'number'),
    cardtrader_image_url: sourceUrl,
    cdn_image_url: row.cdn_image_url || '',
    image_url: row.image_url || '',
  };
}

async function queryBlueprintRows(env) {
  if (!env.MARKETPLACE_DATABASE_URL) {
    throw new Error('Missing MARKETPLACE_DATABASE_URL.');
  }

  const client = new Client({
    connectionString: env.MARKETPLACE_DATABASE_URL,
    ssl: env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' ? { rejectUnauthorized: true } : false,
    statement_timeout: 120000,
  });

  await client.connect();
  try {
    const result = await client.query(`
      select
        b.id::text as blueprint_id,
        b.name,
        b.version,
        coalesce(nullif(b.expansion->>'name',''), nullif(b.blueprint->>'expansion_name',''), '') as set_name,
        coalesce(nullif(b.blueprint->>'rarity',''), nullif(b.blueprint->>'collector_rarity',''), '') as rarity,
        b.image_url,
        b.cardtrader_image_url,
        b.cdn_image_url,
        b.cdn_object_key,
        b.blueprint #>> '{image,url}' as blueprint_image_url,
        b.editable_properties
      from public.cardtrader_pokemon_blueprints b
      where coalesce(nullif(b.cdn_object_key,''), nullif(b.cardtrader_image_url,''), nullif(b.blueprint #>> '{image,url}','')) is not null
      order by b.id
    `);
    return result.rows;
  } finally {
    await client.end();
  }
}

function uploadToR2(args, env) {
  const commandEnv = { ...process.env, ...env };
  if (!commandEnv.CLOUDFLARE_API_KEY && commandEnv.CLOUDFLARE_GLOBAL_API_KEY) {
    commandEnv.CLOUDFLARE_API_KEY = commandEnv.CLOUDFLARE_GLOBAL_API_KEY;
  }
  if (!commandEnv.CLOUDFLARE_EMAIL && commandEnv.CLOUDFLARE_API_EMAIL) {
    commandEnv.CLOUDFLARE_EMAIL = commandEnv.CLOUDFLARE_API_EMAIL;
  }
  execFileSync(
    'npx',
    [
      'wrangler',
      'r2',
      'object',
      'put',
      `${args.bucket}/${args.r2Key}`,
      '--file',
      args.output,
      '--content-type',
      'application/json',
      '--remote',
    ],
    {
      env: commandEnv,
      stdio: 'inherit',
    }
  );
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const env = readEnv(args.envFile);
  const rows = await queryBlueprintRows(env);
  const objects = [];
  const skipped = { noUsableUrl: 0 };

  for (const row of rows) {
    const mapped = mapBlueprintRow(row, args.publicBaseUrl);
    if (mapped) objects.push(mapped);
    else skipped.noUsableUrl += 1;
  }

  const payload = {
    generated_at: new Date().toISOString(),
    source: 'oracle.public.cardtrader_pokemon_blueprints',
    strategy: 'one best non-homepage image per blueprint; prefer R2 object, fallback CardTrader source URL',
    count: objects.length,
    skipped,
    objects,
  };

  fs.mkdirSync(require('path').dirname(args.output), { recursive: true });
  fs.writeFileSync(args.output, JSON.stringify(payload));
  console.log(JSON.stringify({
    output: args.output,
    count: objects.length,
    skipped,
    r2Upload: args.uploadR2 ? `${args.bucket}/${args.r2Key}` : null,
  }, null, 2));

  if (args.uploadR2) {
    uploadToR2(args, env);
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
