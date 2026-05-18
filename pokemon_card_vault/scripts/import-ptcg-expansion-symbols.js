const fs = require('fs');
const path = require('path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');

function readEnv(filePath) {
  const values = {};
  if (!fs.existsSync(filePath)) {
    return { ...process.env };
  }
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) {
      continue;
    }
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return { ...values, ...process.env };
}

function required(env, key) {
  if (!env[key]) {
    throw new Error(`Missing ${key}`);
  }
  return env[key];
}

function slugify(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140);
}

function normalizeName(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/pokemon/g, '')
    .replace(/pokémon/g, '')
    .replace(/tcg/g, '')
    .replace(/&/g, ' and ')
    .replace(/\bex\b/g, ' ex ')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function aliasesForExpansion(expansion) {
  const aliases = new Set();
  const code = String(expansion.code || '').trim().toLowerCase();
  const name = String(expansion.name || '').trim();
  const directAliases = {
    bs: 'base1',
    ju: 'base2',
    fo: 'base3',
    b2: 'base4',
    tr: 'base5',
    g1: 'gym1',
    g2: 'gym2',
    n1: 'neo1',
    n2: 'neo2',
    si: 'si1',
    n3: 'neo3',
    n4: 'neo4',
    lc: 'base6',
    ex: 'ecard1',
    aq: 'ecard2',
    skg: 'ecard3',
    rs: 'ex1',
    ss: 'ex2',
    dr: 'ex3',
    hl: 'ex4',
    rg: 'ex6',
    trr: 'ex7',
    dx: 'ex8',
    em: 'ex9',
    uf: 'ex10',
    ds: 'ex11',
    lm: 'ex12',
    hp: 'ex13',
    cg: 'ex14',
    df: 'ex15',
    pk: 'ex16',
    dp: 'dp1',
    mt: 'dp2',
    sw: 'dp3',
    ge: 'dp4',
    md: 'dp5',
    la: 'dp6',
    sft: 'dp7',
    pl: 'pl1',
    rr: 'pl2',
    sv: 'pl3',
    ar: 'pl4',
    hgs: 'hgss1',
    ul: 'hgss2',
    und: 'hgss3',
    tri: 'hgss4',
    clo: 'col1',
    blw: 'bw1',
    epo: 'bw2',
    nvi: 'bw3',
    nxd: 'bw4',
    dex: 'bw5',
    drx: 'bw6',
    drv: 'dv1',
    bcr: 'bw7',
    pls: 'bw8',
    plf: 'bw9',
    plb: 'bw10',
    ltr: 'bw11',
    kss: 'xy0',
    'xy-en': 'xy1',
    flf: 'xy2',
    ffi: 'xy3',
    phf: 'xy4',
    prc: 'xy5',
    dcr: 'dc1',
    ros: 'xy6',
    aor: 'xy7',
    bkt: 'xy8',
    bkp: 'xy9',
    gen: 'xy10',
    fco: 'xy10',
    sts: 'xy11',
    evo: 'xy12',
    sum: 'sm1',
    gri: 'sm2',
    bus: 'sm3',
    slg: 'sm35',
    cinv: 'sm4',
    upr: 'sm5',
    fli: 'sm6',
    ces: 'sm7',
    drm: 'sm75',
    lot: 'sm8',
    teu: 'sm9',
    unb: 'sm10',
    unm: 'sm11',
    hif: 'sm115',
    cec: 'sm12',
    ssh: 'swsh1',
    rcl: 'swsh2',
    daa: 'swsh3',
    cp: 'swsh35',
    viv: 'swsh4',
    shf: 'swsh45',
    bst: 'swsh5',
    cre: 'swsh6',
    evs: 'swsh7',
    cel: 'cel25',
    fst: 'swsh8',
    bsr: 'swsh9',
    asr: 'swsh10',
    pgo: 'pgo',
    lor: 'swsh11',
    sit: 'swsh12',
    crz: 'swsh12pt5',
    svi: 'sv1',
    pa: 'sv2',
    pal: 'sv2',
    obf: 'sv3',
    mew: 'sv3pt5',
    par: 'sv4',
    paf: 'sv4pt5',
    tef: 'sv5',
    twm: 'sv6',
    sfa: 'sv6pt5',
    scr: 'sv7',
    ssp: 'sv8',
    pre: 'sv8pt5',
    jtt: 'sv9',
    dri: 'sv10',
    det: 'det1',
    bwbsp: 'bwp',
    xybsp: 'xyp',
    smbs: 'smp',
    swshbs: 'swshp',
    svp: 'svp',
  };
  if (code) aliases.add(code);
  if (directAliases[code]) aliases.add(directAliases[code]);
  if (name) aliases.add(slugify(name));
  if (code === 'pa') aliases.add('sv2');
  if (code === 'obf') aliases.add('sv3');
  if (code === 'mew') aliases.add('sv3pt5');
  if (code === 'par') aliases.add('sv4');
  if (code === 'paf') aliases.add('sv4pt5');
  if (code === 'tef') aliases.add('sv5');
  if (code === 'twm') aliases.add('sv6');
  if (code === 'sfa') aliases.add('sv6pt5');
  if (code === 'scr') aliases.add('sv7');
  if (code === 'ssp') aliases.add('sv8');
  if (code === 'pre') aliases.add('sv8pt5');
  if (code === 'jtt') aliases.add('sv9');
  if (code === 'dri') aliases.add('sv10');
  if (code === 'cel') aliases.add('cel25');
  if (code === 'celc') aliases.add('cel25c');
  if (code === 'det') aliases.add('det1');
  if (code === 'pgo') aliases.add('pgo');
  return [...aliases].filter(Boolean);
}

function readExpansions() {
  const filePath = path.resolve('data/cardtrader/pokemon-expansions.json');
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function listAssetSymbols(assetRoot) {
  const entries = fs.readdirSync(assetRoot, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const code = entry.name;
      const symbolPath = path.join(assetRoot, code, 'symbol.png');
      if (!fs.existsSync(symbolPath)) {
        return null;
      }
      return { code, symbolPath };
    })
    .filter(Boolean);
}

async function upsertExpansion(env, row) {
  const response = await fetch(
    `${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/cardtrader_pokemon_expansions`,
    {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify(row),
    },
  );
  if (!response.ok) {
    throw new Error(`Expansion upsert failed ${response.status}: ${await response.text()}`);
  }
}

async function main() {
  const env = readEnv(path.resolve('.env.local'));
  required(env, 'CLOUDFLARE_ACCOUNT_ID');
  required(env, 'R2_ACCESS_KEY_ID');
  required(env, 'R2_SECRET_ACCESS_KEY');
  required(env, 'SUPABASE_URL');
  required(env, 'SUPABASE_SERVICE_ROLE_KEY');

  const assetRoot = path.resolve(
    process.env.PTCG_ASSETS_DIR || '../ptcg-assets',
  );
  if (!fs.existsSync(assetRoot)) {
    throw new Error(`PTCG assets directory not found: ${assetRoot}`);
  }

  const bucket = env.POKOIN_CARD_IMAGES_BUCKET || 'cardvault-images';
  const cdnBase = (env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com')
    .replace(/\/$/, '');
  const dryRun = process.env.DRY_RUN === '1';
  const limit = Number(process.env.SYMBOL_MAX_ROWS || 0);
  const onlyCodes = new Set(
    String(process.env.SYMBOL_CODES || '')
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean),
  );

  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });

  const assets = new Map(
    listAssetSymbols(assetRoot).map((asset) => [asset.code.toLowerCase(), asset]),
  );
  const expansions = readExpansions();
  let matched = 0;
  let uploaded = 0;
  let missing = 0;

  for (const expansion of expansions) {
    if (limit > 0 && matched >= limit) break;
    const aliases = aliasesForExpansion(expansion);
    const asset = aliases.map((alias) => assets.get(alias)).find(Boolean);
    if (!asset) {
      missing += 1;
      continue;
    }
    if (onlyCodes.size > 0 && !onlyCodes.has(asset.code.toLowerCase()) && !onlyCodes.has(String(expansion.code || '').toLowerCase())) {
      continue;
    }

    matched += 1;
    const ext = 'png';
    const objectKey = `expansions/symbols/${slugify(expansion.name)}.${ext}`;
    const symbolImageUrl = `${cdnBase}/${objectKey}`;
    const row = {
      expansion_id: expansion.id,
      game_id: expansion.game_id || 5,
      code: expansion.code || null,
      name: expansion.name,
      source_asset_code: asset.code,
      symbol_image_url: symbolImageUrl,
      symbol_object_key: objectKey,
      symbol_imported_at: new Date().toISOString(),
    };

    if (dryRun) {
      console.log(`match ${expansion.code || ''} "${expansion.name}" <- ${asset.code}`);
      continue;
    }

    await client.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: objectKey,
        Body: fs.readFileSync(asset.symbolPath),
        ContentType: 'image/png',
        CacheControl: 'public, max-age=31536000, immutable',
      }),
    );
    await upsertExpansion(env, row);
    uploaded += 1;
    console.log(`uploaded ${expansion.id} ${expansion.code || ''}: ${objectKey} <- ${asset.code}`);
  }

  console.log(`matched ${matched}, uploaded ${uploaded}, missing ${missing}, assets ${assets.size}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
