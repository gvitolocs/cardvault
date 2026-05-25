
const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');
const pokoinposRoot = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const ids = ['113087','274258','383285','110803','145456'];
const env = {};
for (const file of ['.env.local', path.join(pokoinposRoot, 'deploy/env/peer4-postgres.env')]) {
  if (!fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const i = trimmed.indexOf('=');
    env[trimmed.slice(0, i).replace(/^export\s+/, '').trim()] = trimmed.slice(i + 1).trim().replace(/^['"]|['"]$/g, '');
  }
}
Object.assign(env, process.env);
const dbUrl = env.MARKETPLACE_DATABASE_URL || `postgresql://${encodeURIComponent(env.MARKETPLACE_DB_USER)}:${encodeURIComponent(env.MARKETPLACE_DB_PASSWORD)}@${env.MARKETPLACE_DB_PUBLIC_HOST}:${env.MARKETPLACE_DB_PORT || '5432'}/${encodeURIComponent(env.MARKETPLACE_DB_NAME)}`;
const expansions = JSON.parse(fs.readFileSync('data/cardtrader/pokemon-expansions.json','utf8'));
const expansionCodeByName = new Map(expansions.map(r => [String(r.name||'').toLowerCase(), String(r.code||'')]));
const knownSetCodes = new Map([['Rocket Gang Strikes Back','PCG3'],['Skyridge','SK'],['Start Deck 100','sI100'],['Neo Discovery','NDI'],['Clash at the Summit','L3'],['CS1b: Dynamax Clash - Flame','CS1bC'],['CSM1c: Storming Emergence - Abundant','CSM1cC'],['SWSH Black Star Promos','SWSH'],['SM Black Star Promos','OSSM']]);
const knownExpansionSlugs = new Map([['CS1b: Dynamax Clash - Flame','Dynamax-Clash-Flame'],['CSM1c: Storming Emergence - Abundant','Storming-Emergence-Abundant'],['S-P: Sword & Shield Promos','Sword-Shield-Simplified-Chinese-Promos'],['World Championship Decks 2007','WCD-2007']]);
const nameOnlyTrainerExpansions = new Set(['Night Unison','Rising Fist']);
function slugPart(v){return String(v||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/&/g,' and ').replace(/[^a-zA-Z0-9]+/g,'-').replace(/^-+|-+$/g,'')}
function cardNameSlug(n){return slugPart(String(n||'').replace(/\bShiny Rare\b/gi,'').replace(/\bRare Holo\b/gi,'').replace(/\bHolo\b/gi,'').replace(/\s+/g,' ').trim())}
function normNo(v){const t=String(v||'').replace(/\|\|/g,'|').trim(); const s=/([A-Z]*\d+[A-Z]?\s*\/\s*\d+)/i.exec(t); if(s)return s[1].replace(/\s+/g,''); const sp=/\b([A-Z]{1,4}\s*\d+)\b/i.exec(t); if(sp)return sp[1].replace(/\s+/g,''); const st=/\bStamp Number\s+(\d+)\b/i.exec(t); if(st)return st[1]; const p=/\b(?:No\.)?0*(\d{1,4})\b/i.exec(t); return p?p[1]:t}
function setCode(row){return knownSetCodes.get(row.expansion_name)||(row.expansion_code||expansionCodeByName.get(String(row.expansion_name||'').toLowerCase())||'').replace(/[^a-z0-9]/gi,'').toUpperCase()}
function codes(raw, code){const c=normNo(raw).replace(/\s+/g,'').replace(/\/.*$/,'').toUpperCase(); if(!c||!code||!/\d/.test(c))return[]; const special=/^([A-Z]+)(\d+)$/.exec(c); if(special){const value=Number(special[2]); return [`${code}${special[1]}${String(value).padStart(2,'0')}`,`${code}${special[1]}${special[2]}`,`${code}${special[1]}${String(value).padStart(3,'0')}`] } const n=/^0*(\d+)[A-Z]?$/.exec(c); if(!n)return[`${code}${c}`]; const val=Number(n[1]); return c.startsWith('0')?[`${code}${String(val).padStart(3,'0')}`,`${code}${val}`,`${code}${String(val).padStart(2,'0')}`]:[`${code}${val}`,`${code}${String(val).padStart(3,'0')}`,`${code}${String(val).padStart(2,'0')}`]}
function expansionSlug(row){return knownExpansionSlugs.get(row.expansion_name)||slugPart(row.expansion_name)}
function parserUrl(row){const name=cardNameSlug(row.name); const exp=expansionSlug(row); const type=String(row.card_type||'').toLowerCase(); const nameOnly=`https://www.cardmarket.com/en/Pokemon/Products/Singles/${exp}/${name}`; if(/\b(trainer|supporter|item|stadium|tool|special energy|energy)\b/.test(type)&&nameOnlyTrainerExpansions.has(row.expansion_name))return nameOnly; const product=codes(row.expansion_number, setCode(row))[0]; if(!product)return nameOnly; const marker = /^v\d+$/i.test(String(row.product_variant||'')) ? `${String(row.product_variant).toUpperCase()}-` : ''; return `https://www.cardmarket.com/en/Pokemon/Products/Singles/${exp}/${name}-${marker}${product}`;}
function normalize(v){return String(v||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim()}
async function fetchJson(url){const r=await fetch(url); if(!r.ok)return null; return r.json()}
(async()=>{
 const tcgdexCards = await fetchJson('https://api.tcgdex.net/v2/en/cards');
 const byName = new Map();
 for (const c of tcgdexCards || []) { const k=normalize(c.name); if(!byName.has(k))byName.set(k,[]); byName.get(k).push(c); }
 const pool = new Pool({ connectionString: dbUrl, ssl:{rejectUnauthorized:false}, max:2 });
 const result = await pool.query(`
   select v.card_id::text as card_id, v.name, v.expansion_name, v.expansion_number,
          coalesce(nullif(v.product_variant,''), '') as product_variant,
          e.code as expansion_code, c.card_type, b.card_market_ids
   from public.marketplace_card_versions v
   left join public.cardtrader_pokemon_expansions e on e.name = v.expansion_name
   left join public.marketplace_cards c on c.card_id = v.card_id
   left join public.cardtrader_pokemon_blueprints b on b.id::text = v.card_id::text
   where v.card_id::text = any($1::text[])
 `, [ids]);
 await pool.end();
 const rowsById = new Map(result.rows.map(r => [String(r.card_id), r]));
 for (const id of ids) {
   const row = rowsById.get(id);
   const targetNumber = normNo(row.expansion_number).replace(/\/.*$/,'').replace(/^0+/,'');
   const matches = (byName.get(normalize(row.name)) || []).filter(c => String(c.localId||'').replace(/^0+/,'') === targetNumber);
   const apiSetIds = [...new Set(matches.map(c => String(c.id||'').split('-')[0]).filter(Boolean))].slice(0,3);
   const apiCode = apiSetIds[0] ? apiSetIds[0].replace(/[^a-z0-9]/gi,'').toUpperCase() : setCode(row);
   const apiProduct = codes(row.expansion_number, apiCode)[0];
   const apiUrl = apiProduct ? `https://www.cardmarket.com/en/Pokemon/Products/Singles/${expansionSlug(row)}/${cardNameSlug(row.name)}-${apiProduct}` : parserUrl(row);
   console.log(JSON.stringify({blueprint:id, card:row.name, expansion:row.expansion_name, number:row.expansion_number, parser:parserUrl(row), apiAssisted:apiUrl, tcgdexMatches:matches.length, tcgdexSetIds:apiSetIds, note:matches.length ? 'TCGdex name+number only; set alignment not proven' : 'No TCGdex name+number match; falls back to local expansion code'}));
 }
})();
