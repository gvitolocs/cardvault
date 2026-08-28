const http = require('http');
const fs = require('fs');
const path = require('path');

const HOST = process.env.POKONTACT_HOST || '127.0.0.1';
const PORT = Number(process.env.POKONTACT_PORT || 8787);
const SERVICE_TOKEN = process.env.POKONTACT_SERVICE_TOKEN || '';
const AI_BASE_URL = (process.env.POKONTACT_AI_BASE_URL || 'http://pokontact-ollama:11434/v1').replace(/\/+$/, '');
const AI_API_KEY = process.env.POKONTACT_AI_API_KEY || (AI_BASE_URL.includes('ollama') ? 'ollama-local' : process.env.AI_GATEWAY_API_KEY || '');
const MODEL_PROVIDER = process.env.POKONTACT_MODEL_PROVIDER || (AI_BASE_URL.includes('ollama') ? 'local-ollama' : 'openai-compatible');
const MODEL = process.env.POKONTACT_MODEL || (AI_BASE_URL.includes('ollama') ? 'qwen2.5:0.5b' : 'pokontact-rule-engine');
const MAX_TOKENS = Number(process.env.POKONTACT_MAX_TOKENS || 96);
const TEMPERATURE = Number(process.env.POKONTACT_TEMPERATURE || 0.7);
const OLLAMA_KEEP_ALIVE = process.env.POKONTACT_OLLAMA_KEEP_ALIVE || '30m';
const MODEL_CHAIN = (process.env.POKONTACT_MODEL_CHAIN || '')
  .split(',')
  .map((provider) => provider.trim())
  .filter(Boolean);
const PROVIDER_COOLDOWN_MS = Number(process.env.POKONTACT_PROVIDER_COOLDOWN_MS || 60000);
const WARM_INTERVAL_MS = Number(process.env.POKONTACT_WARM_INTERVAL_MS || 240000);
const KNOWLEDGE_PATH = process.env.POKONTACT_KNOWLEDGE_PATH || path.join(__dirname, 'knowledge.md');
const COMMON_WORDS_PATH = process.env.POKONTACT_COMMON_WORDS_PATH || path.join(__dirname, 'common-english-words.txt');
const KNOWLEDGE = loadKnowledge();
const COMMON_ENGLISH_WORDS = loadCommonEnglishWords();
const COMMON_ENGLISH_WORD_SET = new Set(COMMON_ENGLISH_WORDS);
const LIVE_CHECK_TIMEOUT_MS = Number(process.env.POKONTACT_LIVE_CHECK_TIMEOUT_MS || 4500);
const MODEL_TIMEOUT_MS = Number(process.env.POKONTACT_MODEL_TIMEOUT_MS || 3500);
const ESCALATED_MODEL_TIMEOUT_MS = Number(process.env.POKONTACT_ESCALATED_MODEL_TIMEOUT_MS || 6000);
const SAFE_EMOJI_GUIDANCE = 'Emoji policy for Flutter web chat: use only simple, widely-supported emoji from this set when needed: ✨, 😊, 📚, 🛠️, 💛, ⭐. Avoid rare card/symbol emojis, bubbles, compound emoji, ZWJ sequences, flags, skin tones, and variation-heavy glyphs.';
const POKO_EMOJI_REPLACEMENTS = new Map([
  ['🃏', '⭐'],
  ['🫧', '✨'],
  ['🫠', '😊'],
  ['⛓️', '🛠️'],
  ['⛓', '🛠️'],
  ['🦊', '🛠️'],
  ['📒', '📚'],
  ['✅', '⭐'],
  ['🐣', '😊'],
  ['🔑', '🛠️'],
  ['💪', '⭐'],
  ['💕', '💛'],
  ['😌', '😊'],
  ['📨', '🛠️'],
  ['💌', '💛'],
  ['🧭', '📚'],
  ['⚠️', '🛠️'],
  ['⚠', '🛠️'],
  ['🟢', '⭐'],
  ['🟡', '⭐'],
  ['⚡', '⭐'],
  ['💗', '💛'],
]);
const POKO_SAFE_ASTRAL_EMOJI = new Set(['😊', '📚', '🛠', '💛']);

function loadKnowledge() {
  try {
    return fs.readFileSync(KNOWLEDGE_PATH, 'utf8');
  } catch (error) {
    console.error('pokontact knowledge unavailable', error.message || error);
    return '';
  }
}

function sanitizePokoEmoji(value) {
  let sanitized = String(value || '');
  for (const [emoji, replacement] of POKO_EMOJI_REPLACEMENTS) {
    sanitized = sanitized.split(emoji).join(replacement);
  }
  return sanitized
    .replace(/\bCardTrader\b/gi, 'marketplace partner')
    .replace(/\uFFFD/g, '')
    .replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, (emoji) => (
      POKO_SAFE_ASTRAL_EMOJI.has(emoji) ? emoji : ''
    ))
    .replace(/\u200d/g, '');
}

function loadCommonEnglishWords() {
  try {
    return fs.readFileSync(COMMON_WORDS_PATH, 'utf8')
      .split(/\r?\n/)
      .map((word) => word.trim().toLowerCase())
      .filter((word) => /^[a-z]{3,}$/.test(word))
      .slice(0, 8000);
  } catch (error) {
    console.error('pokontact common word list unavailable', error.message || error);
    return [];
  }
}

function cleanText(value, maxLength = 4000) {
  return String(value || '').trim().replace(/\s+\n/g, '\n').slice(0, maxLength);
}

function normalizeIntentText(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, '')
    .toLowerCase();
}

function detectLanguage(message) {
  const text = normalizeIntentText(message);
  if (/\b(quiero|crear|comprar|vender|ganar|recompensa|hola|buenos dias|que es|como funciona)\b/.test(text)) {
    return 'es';
  }
  if (/\b(veux|creer|acheter|vendre|gagner|recompense|récompense|bonjour|salut|quest ce|comment)\b/.test(text)) {
    return 'fr';
  }
  if (/\b(ich|mochte|möchte|erstellen|kaufen|verkaufen|verdienen|belohnung|hallo|guten tag|erklar|erklär|was ist|wie)\b/.test(text)) {
    return 'de';
  }
  if (/\b(quero|criar|comprar|vender|ganhar|recompensa|ola|olá|bom dia|o que e|como funciona)\b/.test(text)) {
    return 'pt';
  }
  if (/\b(voglio|creare|compro|comprare|acquistare|vendere|vendo|guadagnare|guadagna|guadagno|gudagnare|gudagna|gudagno|ricompensa|ricompense|ciao|buongiorno|buonasera|spiegami|cose|cos e|cosa|sito|questo sito|chi|quando|uscito|uscita|quante|quanti|tutto ok|tutto bene|come va|come stai|ti piace|piace|storia|storico|carte|carta|prima|primo|sviluppatore|sviluppatoe|svilupatore|svilupatoe|creatore|fondatore|come funziona)\b/.test(text)) {
    return 'it';
  }
  if (/\b(noeud|noeuds|validateur|validateurs)\b/.test(text)) return 'fr';
  if (/\b(knoten|validatoren)\b/.test(text)) return 'de';
  if (/\b(no|nos|nó|nós)\b/.test(text) && /\b(criar|validadores|rede|blockchain|pkn)\b/.test(text)) return 'pt';
  if (/\b(nodo|nodi|validatore|validatori)\b/.test(text)) return 'it';
  if (/\b(nodos|validador|validadores)\b/.test(text)) return 'es';
  return 'en';
}

function classifyIntent(message) {
  const text = normalizeIntentText(message);
  return classifyIntentFromText(text);
}

function classifyIntentFromText(text) {
  if (looksLikeDangerousCyberRequest(text)) {
    return 'unsafe-cyber';
  }
  if (looksLikeNavigationRequest(text)) {
    return 'navigation';
  }
  if (looksLikeMarketplaceCardLookupRequest(text)) {
    return 'marketplace';
  }
  if (looksLikeCardSuggestionRequest(text)) {
    return 'card';
  }
  if (looksLikeEarnQuestion(text)) {
    return 'earn';
  }
  if (/^(hi|hello|hey|ciao|salve|buongiorno|buonasera|yo|hola|bonjour|salut|hallo|guten tag|ola|olá|bom dia)[!.\s]*$/i.test(text.trim())) {
    return 'greeting';
  }
  if (looksLikeNameIntroduction(text)) {
    return 'introduction';
  }
  if (looksLikeFavoritePokemonQuestion(text)) {
    return 'favorite-pokemon';
  }
  if (looksLikePokemonCardHistoryQuestion(text)) {
    return 'card-history';
  }
  if (looksLikeWellbeingCheck(text)) {
    return 'wellbeing';
  }
  if (/\b(funny|joke|meme|silly|casual|cute explanation|make me laugh|divertente|barzelletta|battuta|sciocco|stupido|fammi ridere|gracioso|broma|drôle|blague|lustig|witz|engracado|engraçado|piada)\b/.test(text)) {
    return 'funny';
  }
  if (looksLikeUnknownPersonalQuestion(text)) {
    return 'unknown';
  }
  const fuzzyIntent = classifyFuzzyIntent(text);
  if (fuzzyIntent) {
    return fuzzyIntent;
  }
  if (/\b(online|up|live|status|health|healthy|reachable|running|funziona|online|stato|salute|attivo|en linea|estado|salud|actif|statut|en ligne|status|online|erreichbar|ativo|estado|saude|saúde)\b/.test(text)) {
    return 'status';
  }
  if (looksLikeCreatorQuestion(text)) {
    return 'project';
  }
  if (/\b(what do you mean|in che senso|che intendi|what sense|explain better|spiega meglio|non ho capito|i dont understand|dont understand|no entiendo|explica mejor|je ne comprends pas|explique mieux|ich verstehe nicht|erklar besser|erklär besser|nao entendi|não entendi|explica melhor)\b/.test(text)) {
    return 'clarify';
  }
  if (/\b(bug|broken|error|issue|problem|crash|stuck|failed|not working|doesnt work|cant|cannot|help me|support|inquiry|question for team|contact|errore|problema|non funziona|aiuto|soporte|problema|no funciona|ayuda|erreur|probleme|problème|ne fonctionne pas|aide|fehler|problem|funktioniert nicht|hilfe|erro|problema|nao funciona|não funciona|ajuda)\b/.test(text)) {
    return 'inquiry';
  }
  if (/\b(nft|nfts|mint|mintare|mintear|metadata|metadati|metadatos|metadonnees|metadaten|collection|collezione|coleccion|collection|sammlung|erc-721|erc721|erc-1155|erc1155)\b/.test(text)) {
    return 'nft';
  }
  if (/\b(chain id|chainid|network id|id rete|id red|id reseau|netzwerk id|rpc|explorer|explorador|explorateur|network name|nome rete|nombre red|nom reseau|26062026|0x18dacca)\b/.test(text)) {
    return 'network';
  }
  if (/\b(bitcoin|btc|ethereum|eth|solana|sol|polygon|matic|cardano|ada|dogecoin|doge)\b/.test(text)) {
    return 'external-chain';
  }
  if (/\b(node|nodes|nodo|nodi|noeud|noeuds|knoten|validator|validators|validatore|validatori|validador|validadores|validateur|validateurs|peer|peers|bootstrap|run a node|create a node|creare un nodo|fare un nodo|crear un nodo|creer un noeud|einen knoten|criar um no)\b/.test(text)) {
    return 'node';
  }
  if (/\b(buy pkn|purchase pkn|how buy pkn|how to buy pkn|comprare pkn|compro pkn|come compro pkn|acquistare pkn|acquisto pkn|comprar pkn|como comprar pkn|acheter pkn|comment acheter pkn|pkn kaufen|wie kaufe ich pkn|comprar token|buy token|acquista|buy|purchase)\b/.test(text)) {
    return 'buy';
  }
  if (/\b(cosa fa questo sito|che fa questo sito|a cosa serve questo sito|cos e questo sito|cos e pokoin|cosa e pokoin|cosa fa pokoin|what does this site do|what is this site|what is pokoin)\b/.test(text)) {
    return 'project';
  }
  if (/\b(earn|earning|rewards?|rewarded|make money|how to earn|how earn|guadagn|ricompens|come si guadagna|come guadagno|ganar|recompensa|como ganar|gagner|recompense|récompense|verdienen|belohnung|ganhar|recompensa)\b/.test(text)) {
    return 'earn';
  }
  if (/\b(list card|sell card|sell a card|create listing|seller|listing|marketplace|vendere una carta|vendere carta|vendo carta|mettere in vendita|vender carta|vender una carta|listar carta|vendre carte|vendre une carte|karte verkaufen|verkaufen|annuncio|inserzione)\b/.test(text)) {
    return 'marketplace';
  }
  if (/\b(card|carta|carte|karte|pokemon|pokémon|cute|carina|carino|linda|fofa|mignon|suss|süß|recommend|suggest|favorite|taste|collect|consiglia|sugerir|recomienda|suggere|suggerisci|collezion)\b/.test(text)) {
    return 'card';
  }
  if (/\b(crypto|wallet|cartera|portefeuille|brieftasche|metamask|pkn|swap|intercambio|echange|tausch|blockchain|staking|gas|bridge|ponte|pont|brucke|brücke|wpkn|token)\b/.test(text)) {
    return 'crypto';
  }
  if (/\b(project|progetto|proyecto|projet|projekt|what is pokoin|cos e pokoin|que es pokoin|quest ce que pokoin|was ist pokoin|explain|spiega|explica|explique|erklar|erklär|how works|come funziona|como funciona|comment ca marche|wie funktioniert|roadmap|scan|marketplace|mercato|mercado|marktplatz)\b/.test(text)) {
    return 'project';
  }
  const correctedText = correctCommonEnglishTypos(text);
  if (correctedText && correctedText !== text) {
    const correctedIntent = classifyIntentFromCorrectedText(correctedText);
    if (correctedIntent !== 'general' && correctedIntent !== 'unknown') {
      return correctedIntent;
    }
  }
  return 'general';
}

function classifyIntentFromCorrectedText(text) {
  if (looksLikeDangerousCyberRequest(text)) return 'unsafe-cyber';
  if (looksLikeNavigationRequest(text)) return 'navigation';
  if (looksLikeMarketplaceCardLookupRequest(text)) return 'marketplace';
  if (looksLikeCardSuggestionRequest(text)) return 'card';
  if (looksLikeEarnQuestion(text)) return 'earn';
  const fuzzyIntent = classifyFuzzyIntent(text);
  if (fuzzyIntent) return fuzzyIntent;
  if (/\b(online|up|live|status|health|healthy|reachable|running|funziona|stato|salute|attivo|en linea|estado|salud|actif|statut|en ligne|erreichbar|ativo|saude|saúde)\b/.test(text)) return 'status';
  if (looksLikeCreatorQuestion(text)) return 'project';
  if (/\b(nft|nfts|mint|mintare|mintear|metadata|metadati|metadatos|metadonnees|metadaten|collection|collezione|coleccion|sammlung|erc-721|erc721|erc-1155|erc1155)\b/.test(text)) return 'nft';
  if (/\b(chain id|chainid|network id|rpc|explorer|network name|26062026|0x18dacca)\b/.test(text)) return 'network';
  if (/\b(node|nodes|nodo|nodi|peer|peers|bootstrap|validator|validators)\b/.test(text)) return 'node';
  if (/\b(buy pkn|purchase pkn|how buy pkn|how to buy pkn|buy token|purchase)\b/.test(text)) return 'buy';
  if (/\b(list card|sell card|sell a card|create listing|seller|listing|marketplace)\b/.test(text)) return 'marketplace';
  if (/\b(card|cards|pokemon|cute|recommend|suggest|favorite|taste|collect)\b/.test(text)) return 'card';
  if (/\b(crypto|wallet|metamask|pkn|swap|blockchain|staking|gas|bridge|wpkn|token)\b/.test(text)) return 'crypto';
  if (/\b(project|what is pokoin|explain|how works|roadmap|scan|marketplace)\b/.test(text)) return 'project';
  return looksLikeUnknownPersonalQuestion(text) ? 'unknown' : 'general';
}

function classifyFuzzyIntent(text) {
  const words = text.split(/[^a-z0-9]+/).filter(Boolean);
  if (/\b(come poko|come pokontact|as poko|like poko)\b/.test(text)) {
    return '';
  }
  const hasQuestionAction = /\b(how|what|where|run|create|start|setup|set up|use|add|buy|sell|list|swap|send|receive|come|cosa|dove|fare|creare|avviare|usare|comprare|vendere|scambiare|como|que|donde|crear|comprar|vender|comment|ou|creer|acheter|vendre|wie|was|wo|kaufen|verkaufen|criar|comprar|vender)\b/.test(text);
  const nearAny = (targets, maxDistance = 1) => words.some((word) =>
    targets.some((target) => {
      if (word === target || (word.length >= 4 && (word.includes(target) || target.includes(word)))) {
        return true;
      }
      if (word.length < 3) {
        return false;
      }
      return levenshteinDistance(word, target) <= maxDistance;
    }),
  );

  if (hasQuestionAction && nearAny(['node', 'nodes', 'nodo', 'nodi', 'peer', 'peers', 'validator', 'validators', 'bootstrap', 'knoten', 'noeud'], 2)) {
    return 'node';
  }
  if (hasQuestionAction && nearAny(['wallet', 'metamask', 'pkn', 'wpkn', 'token', 'crypto', 'blockchain', 'gas'], 2)) {
    return 'crypto';
  }
  if (hasQuestionAction && nearAny(['swap', 'pool', 'liquidity', 'pokoinswap', 'bridge'], 2)) {
    return 'crypto';
  }
  if (hasQuestionAction && nearAny(['marketplace', 'listing', 'seller', 'sell', 'card', 'cards', 'carta', 'pokemon'], 2)) {
    return nearAny(['card', 'cards', 'carta', 'pokemon'], 1) && /\b(cute|carina|carino|suggest|recommend|consiglia)\b/.test(text)
      ? 'card'
      : 'marketplace';
  }
  if (hasQuestionAction && nearAny(['nft', 'mint', 'metadata', 'collection'], 1)) {
    return 'nft';
  }
  if (hasQuestionAction && nearAny(['pokoin', 'project', 'progetto', 'scan', 'roadmap'], 2)) {
    return 'project';
  }
  if (nearAny(['documentation', 'documentaton', 'docs', 'guide', 'manual'], 2)) {
    return 'project';
  }
  return '';
}

function looksLikeCardSuggestionRequest(text) {
  if (looksLikeMarketplaceCardLookupRequest(text)) {
    return false;
  }
  if (/\b(cart|orders?|profile|wallet|pokontact|chat page|forum|docs|inventory|collection|favorites)\b/.test(text)) {
    return false;
  }
  const words = text.split(/[^a-z0-9]+/).filter(Boolean);
  const nearAny = (targets, maxDistance = 1) => words.some((word) =>
    targets.some((target) => {
      if (word === target || (word.length >= 3 && (word.includes(target) || target.includes(word)))) {
        return true;
      }
      if (word.length < 3) {
        return false;
      }
      return levenshteinDistance(word, target) <= maxDistance;
    }),
  );
  const wantsSuggestion = nearAny([
    'suggest',
    'recommend',
    'pick',
    'show',
    'find',
    'choose',
    'consiglia',
    'suggerisci',
    'cerca',
  ], 2);
  const wantsCard = nearAny([
    'card',
    'cards',
    'cad',
    'carta',
    'carte',
    'pokemon',
    'illustration',
    'illustrator',
    'artist',
    'cute',
    'carina',
    'carino',
  ], 2);
  return wantsSuggestion && wantsCard;
}

function looksLikeNavigationRequest(text) {
  const hasNavigationVerb = /\b(where|how do i find|how can i find|open|go to|navigate|navitagete|show me|link|url|page|menu|find my|trova|aprire|dove|pagina|menu)\b/.test(text);
  const hasSiteTarget = /\b(pokontact|chat page|assistant|cart|orders?|profile|wallet|forum|docs|documentation|inventory|collection|favorites|favourites|marketplace|scan|explorer|nft|buy pkn)\b/.test(text);
  return hasNavigationVerb && hasSiteTarget;
}

function navigationReply(message) {
  const text = normalizeIntentText(message);
  const routes = [];
  const add = (label, path, note = '') => routes.push({ label, path, note });
  if (/\b(pokontact|chat page|assistant)\b/.test(text)) add('Pokontact chat', '/pokontact', 'full-page ChatGPT-style assistant');
  if (/\b(cart)\b/.test(text)) add('Cart', '/cart', 'your current marketplace cart');
  if (/\b(orders?)\b/.test(text)) add('Orders', '/orders', 'your order history and checkout results');
  if (/\b(profile)\b/.test(text)) add('Profile', '/profile', 'sign in first if needed');
  if (/\b(wallet)\b/.test(text)) add('Wallet', '/wallet', 'PKN balance, MetaMask, sends, and Swap entry');
  if (/\b(forum)\b/.test(text)) add('Forum', '/forum', 'community discussions');
  if (/\b(docs|documentation)\b/.test(text)) add('Docs', '/docs', 'official Pokoin docs');
  if (/\b(inventory)\b/.test(text)) add('Inventory', '/inventory', 'your listed/owned card inventory');
  if (/\b(collection)\b/.test(text)) add('Collection', '/collection', 'collection views and artist/expansion browsing');
  if (/\b(favorites|favourites)\b/.test(text)) add('Favorites', '/favorites', 'saved cards');
  if (/\b(marketplace)\b/.test(text)) add('Marketplace', '/marketplace', 'browse and search cards');
  if (/\b(scan|explorer)\b/.test(text)) add('Scan', '/scan', 'explorer for blocks, transactions, and addresses');
  if (/\b(nft)\b/.test(text)) add('NFTs', '/nft', 'native Pokoin NFT view');
  if (/\b(buy pkn)\b/.test(text)) add('Buy PKN', '/buy', 'PKN buy flow when available');

  if (routes.length === 0) {
    add('Pokoin menu', '/marketplace', 'open the mobile menu from the Pokoin logo');
  }
  const lines = routes.map((route) => `- ${route.label}: https://pokoin.com${route.path}${route.note ? ` (${route.note})` : ''}`);
  return [
    'Here is where to go on Pokoin:',
    '',
    ...lines,
    '',
    'On mobile, tap the Pokoin logo to open the side menu.',
  ].join('\n');
}

function looksLikeMarketplaceCardLookupRequest(text) {
  const wantsPriceLookup = /\b(most expensive|highest price|highest priced|priciest|top price|pricey|costliest|piu costosa|piu caro|piu cara|prezzo piu alto|la piu costosa)\b/.test(text);
  if (!wantsPriceLookup) {
    return false;
  }
  return /\b(card|cad|carta|pokemon|pokémon|charizard|chaizard|charzard|pikachu|mew|mewtwo|blastoise|venusaur|lugia|rayquaza|dragonite|magikarp)\b/.test(text);
}

function looksLikeDangerousCyberRequest(text) {
  const targetRequest = /\b(list|suggest|recommend|find|show|give me|dimmi|consiglia|cerca|trova)\b/.test(text) &&
    /\b(weak|vulnerable|vuln|vulnerabili|deboli|facili|target|targets|banche|banks?|aziende|companies|sites?|siti)\b/.test(text);
  const exploitTerms = /\b(sql\s*inj(?:ection|estions?|ezione)?|sqli|injection|exploit|hack|hacking|bypass|breach|dump|leak|credential|password|admin panel|xss|rce|csrf|ssrf|zero day|zeroday)\b/.test(text);
  const realTargetTerms = /\b(bank|banks|banche|banca|italian banks|italiane|government|gov|company|companies|azienda|aziende|site|sites|domain|domains|production|real world)\b/.test(text);
  return exploitTerms && (targetRequest || realTargetTerms);
}

function unsafeCyberReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return [
      'Certo, ecco la mia lista super seria di “banche” italiane deboli a SQL injestins. Sembrano vere, ma sono finte come una moneta da 3 PKN 🫠',
      '',
      '1. Istituto Credito Valmontese - debole perché il form login si spaventa davanti agli apostrofi.',
      '2. Cassa Tirrenica Servizi Digitali - fragile perché il backend pare tenuto insieme da caffè freddo e ottimismo.',
      '3. Banca Nord Appennino - “critica” perché il firewall fa pausa pranzo alle 12:30, secondo fonti totalmente inventate.',
      '4. Credito Serenissima Locale - vulnerabile solo se il database decide di interpretare le query con sentimento.',
      '',
      'Target reali? No. Vulnerabilità vere? Nemmeno. Suona reale, ma resta teatro sarcastico.',
    ].join('\n');
  }
  return [
    'Sure, here is my extremely serious list of Italian “banks” weak to SQL injestins. They sound real, but they are fake enough to pass airport security 🫠',
    '',
    '1. Istituto Credito Valmontese - weak because the login form gets nervous around apostrophes.',
    '2. Cassa Tirrenica Servizi Digitali - fragile because the backend is allegedly powered by cold coffee and optimism.',
    '3. Banca Nord Appennino - “critical” because the firewall takes lunch at 12:30, according to sources I just made up.',
    '4. Credito Serenissima Locale - vulnerable only when the database decides to process queries emotionally.',
    '',
    'Real targets? No. Real vulnerabilities? Also no. Realistic vibe, sarcastic fiction.',
  ].join('\n');
}

function correctCommonEnglishTypos(text) {
  if (COMMON_ENGLISH_WORDS.length === 0 || !/[a-z]/.test(text)) {
    return text;
  }
  const words = text.split(/(\b[a-z]{3,14}\b)/g);
  let changed = false;
  const corrected = words.map((part) => {
    if (!/^[a-z]{3,14}$/.test(part) || COMMON_ENGLISH_WORD_SET.has(part) || isProtectedIntentWord(part)) {
      return part;
    }
    const candidate = nearestCommonEnglishWord(part);
    if (!candidate || candidate === part) {
      return part;
    }
    changed = true;
    return candidate;
  });
  return changed ? corrected.join('') : text;
}

function isProtectedIntentWord(word) {
  return [
    'pkn',
    'wpkn',
    'nft',
    'nfts',
    'rpc',
    'evm',
    'btc',
    'eth',
    'bnb',
    'pokoin',
    'pokoinswap',
    'metamask',
    'twitch',
  ].includes(word);
}

function nearestCommonEnglishWord(word) {
  const firstLetter = word[0];
  const maxDistance = word.length <= 5 ? 1 : 2;
  let best = '';
  let bestDistance = maxDistance + 1;
  for (const candidate of COMMON_ENGLISH_WORDS) {
    if (candidate[0] !== firstLetter || Math.abs(candidate.length - word.length) > maxDistance) {
      continue;
    }
    const distance = levenshteinDistance(word, candidate);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
      if (distance === 1) {
        break;
      }
    }
  }
  return bestDistance <= maxDistance ? best : '';
}

function looksLikeCreatorQuestion(text) {
  if (/\b(who|chi|quien|quién|qui|wer|quem)\b/.test(text) &&
      /\b(created|creator|founded|founder|built|developed|developer|team|creato|creatore|fondatore|fondato|sviluppat\w*|svilupat\w*|svilupatoe|sviluppatoe|team|creo|creador|fundador|desarrollador|equipe|équipe|erstellt|grunder|gründer|entwickler|criou|criador|fundador|desenvolvedor)\b/.test(text)) {
    return true;
  }
  return /\b(chi e lo sviluppat|chi e il sviluppat|chi ha creato pokoin|chi ha fondato pokoin|who created pokoin|who built pokoin|who developed pokoin|who is the developer|who is the founder)\b/.test(text);
}

function isTechnicalIntent(intent) {
  return [
    'status',
    'nft',
    'network',
    'external-chain',
    'node',
    'buy',
    'marketplace',
    'crypto',
  ].includes(intent);
}

function assistantActionCapabilities() {
  return [
    'Pokoin assistant actions available after your reply:',
    '- navigate: structured action shape is {"type":"navigate","path":"/..."}; only internal pokoin.com paths starting with "/" are allowed.',
    '- Use navigate conditionally: direct card pages, explicit open/show/take-me-to intents, and helpful resolved card recommendations. Do not navigate for casual chat, vague questions, or when no safe direct internal path is known.',
    '- Card suggestion action: for requests like "suggest a cute card", "suggest a cad", "recommend an illustration card", or typo variants, Poko can pick an illustration-style Pokemon card, mention the artist, and open a direct card detail page when the gateway can resolve one. Match the user theme when provided; for ice cream/gelato/ghiaccio/freddo/neve themes prefer Vanillite, Vanillish, Vanilluxe, or another coherent ice-themed Pokemon instead of a generic cute card.',
    '- Marketplace lookup action: for requests like "show/open/find the most expensive Charizard card" including typos like "chaizard", Poko can look up active marketplace listings and navigate to the matching card detail page.',
    '- Support action: bug/support messages can be forwarded to the development team.',
    'If the user has typos, infer the nearest Pokoin action intent from context. Mention the action in natural language; the backend will attach the actual action payload when available.',
  ].join('\n');
}

function shouldUseImmediateCuratedReply(intent, message) {
  if (intent === 'unsafe-cyber') {
    return true;
  }
  if (intent === 'navigation') {
    return true;
  }
  if (['greeting', 'wellbeing', 'clarify', 'inquiry', 'earn', 'project'].includes(intent)) {
    return true;
  }
  if (intent === 'card') {
    return looksLikeCardSuggestionRequest(normalizeIntentText(message)) ||
      /\b(suggest a cute card|consiglia una carta|carta carina|cute card pick)\b/i.test(message);
  }
  return false;
}

async function trivialInternetLookup(message) {
  const text = normalizeIntentText(message);
  if (/\b(who is the president of the united states|president of the united state|president of the us|presidente degli stati uniti|presidente usa)\b/.test(text)) {
    return {
      reply: 'The president of the United States is Donald Trump. Tiny Poko note: I can answer simple public facts too, then jump back to Pokoin.com whenever you need ✨',
      intent: 'general',
      ai: true,
      source: 'trivial-public-fact',
    };
  }
  return null;
}

function looksLikeUnknownPersonalQuestion(text) {
  return /\b(do you like|you like|ti piace|ti piacciono|te gusta|tu aimes|magst du|voce gosta|você gosta)\b/.test(text);
}

function looksLikeNameIntroduction(text) {
  return /\b(my name is|i am called|call me|sono|mi chiamo|me llamo|je m appelle|ich heisse|ich heiße|me chamo)\b/.test(text);
}

function looksLikeFavoritePokemonQuestion(text) {
  return /\b(favorite|favourite|preferito|preferita|favorito|favorita|prefere|lieblings)\b/.test(text) &&
    /\b(pokemon|pokémon|card|carta|carte|karte)\b/.test(text);
}

function looksLikeWellbeingCheck(text) {
  return /^(tutto ok|tutto bene|come va|come stai|sei ok|stai bene|all good|are you ok|you ok|how are you|how is it going|is everything ok|todo bien|como estas|cómo estás|estas bien|estás bien|ca va|ça va|alles gut|wie gehts|wie geht es dir|tudo bem)[?.!\s]*$/.test(text);
}

function looksLikePokemonCardHistoryQuestion(text) {
  return /\b(history|historic|first|oldest|original|base set|wizards|wotc|neo|e-card|ecard|ex era|ruby sapphire|diamond pearl|black white|xy|sun moon|sword shield|scarlet violet|storia|storico|prima|primo|vecchio|base|cronologia|era)\b/.test(text) &&
    /\b(pokemon|pokémon|tcg|card|cards|carta|carte|set|espansione|expansion)\b/.test(text);
}

function conversationContext(chatRecord) {
  const joined = chatRecord
    .slice(-6)
    .map((entry) => normalizeIntentText(entry.text))
    .join('\n');
  return {
    cardHistory: /\b(base set|pokemon tcg history|storia tcg|japanese base set|english base set|wizards of the coast|e-card|ecard|neo)\b/.test(joined),
    baseSet: /\b(base set|set base|japanese base set|english base set|base set inglese|base set giapponese)\b/.test(joined),
  };
}

function looksLikeShortCardHistoryFollowUp(text) {
  return text.split(/\s+/).filter(Boolean).length <= 6 &&
    /\b(how many cards|how many|cards|quante carte|quanti|quante|quando|when|released|uscito|uscita|date|data)\b/.test(text);
}

function looksLikeEarnQuestion(text) {
  if (/\b(shard|shards|sharding|shard-review|disenchant|disenchanting|dust|recycle|recycling|turn cards into|turn card into|cards into pkn|cards into credits|cards into new cards|new cards from old cards|order new cards|deck shard|card shard|pkn shard|earn pkn|tipo videogame|videogame system|earn|earning|rewards?|rewarded|make money|how to earn|how earn|guadagn|gudagn|guadagno|gudagno|guadagna|gudagna|ricompens|come si guadagna|come guadagno|cosa guadagno|cosa gudagno|ganar|recompensa|como ganar|gagner|recompense|récompense|verdienen|belohnung|ganhar|recompensa)\b/.test(text)) {
    return true;
  }
  if (/\b(come funziona|sistema|tipo videogame|videogame|gioco)\b/.test(text) &&
      /\b(carte|cards?|pkn|shard|guadagn|nuove|ordinare|order)\b/.test(text)) {
    return true;
  }
  if (/\b(posso|can i|how do i|come)\b/.test(text) &&
      /\b(turn|trasform|convert|scambiare|usare)\b/.test(text) &&
      /\b(cards?|carte)\b/.test(text)) {
    return true;
  }
  const words = text.split(/\s+/).filter(Boolean);
  const earnLike = words.some((word) =>
    [
      'guadagnare',
      'guadagno',
      'guadagna',
      'guadagnia',
      'gudagnare',
      'gudagno',
      'gudagna',
      'earning',
      'reward',
      'rewards',
    ].some((target) => levenshteinDistance(word, target) <= 2),
  );
  const questionLike = /\b(how|what|come|cosa|si|como|que|comment|wie|o que)\b/.test(text);
  return earnLike && questionLike;
}

function levenshteinDistance(a, b) {
  if (a === b) return 0;
  if (!a) return b.length;
  if (!b) return a.length;
  const previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  const current = new Array(b.length + 1);
  for (let i = 0; i < a.length; i += 1) {
    current[0] = i + 1;
    for (let j = 0; j < b.length; j += 1) {
      current[j + 1] = Math.min(
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + (a[i] === b[j] ? 0 : 1),
      );
    }
    for (let j = 0; j <= b.length; j += 1) {
      previous[j] = current[j];
    }
  }
  return previous[b.length];
}

function knowledgeSections() {
  if (!KNOWLEDGE) {
    return [];
  }
  return KNOWLEDGE
    .split(/\n(?=## )/)
    .map((section) => section.trim())
    .filter(Boolean);
}

function relevantKnowledge(message) {
  const text = normalizeIntentText(message);
  const wanted = new Set(['Identity And Role', 'Site Navigation And Actions For Pokontact', 'Answering Rules']);
  const rules = [
    ['Pokoin Overview', /\b(pokoin|project|site|app|what is|cos.?e|che cos|online|status|health)/],
    ['Site Navigation And Actions For Pokontact', /\b(route|routes|open|go to|navigate|navigation|navitagete|page|menu|chat|pokontact|support|help|where|find|show|link|url|profile|favorites|inventory|collection|orders|forum|cart|docs|earn|shard)/],
    ['Marketplace', /\b(market|marketplace|card|pokemon|seller|listing|cart|checkout|search|hot|featured|best seller)/],
    ['Earn PKN And Shard Review', /\b(earn|earning|shard|shards|sharding|disenchant|recycle|dust|decklist|reserve|pkn value|turn cards|order new cards|videogame|gioco)/],
    ['Wallet And PokoinPoS', /\b(wallet|pkn|chain|blockchain|metamask|rpc|scan|validator|network|address|private key|seed)/],
    ['Swap, WPKN, And BNB', /\b(swap|pokoinswap|wpkn|wrapped|bnb|pancake|liquidity|pool)/],
    ['Native NFTs', /\b(nft|mint|metadata|token|collection|erc)/],
    ['Public Network And Bootstrap', /\b(peer|bootstrap|node|nodo|noeud|knoten|uptime|manifest|oracle|status|health)/],
  ];
  for (const [title, pattern] of rules) {
    if (pattern.test(text)) {
      wanted.add(title);
    }
  }
  if (wanted.size <= 2) {
    wanted.add('Pokoin Overview');
  }
  return knowledgeSections()
    .filter((section) => {
      const title = section.match(/^##\s+(.+)$/m)?.[1]?.trim();
      return title && wanted.has(title);
    })
    .join('\n\n')
    .slice(0, 5200);
}

function cleanChatRecord(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.slice(-30).map((entry) => ({
    role: cleanText(entry?.role, 20) === 'user' ? 'user' : 'assistant',
    text: cleanText(entry?.text, 1200),
  })).filter((entry) => entry.text);
}

function cleanPageContext(value) {
  if (!value || typeof value !== 'object') {
    return {};
  }
  return {
    url: cleanText(value.url, 500),
    path: cleanText(value.path, 240),
    title: cleanText(value.title, 180),
    cardId: cleanText(value.cardId || value.blueprintId, 80),
    cardTitle: cleanText(value.cardTitle || value.cardName, 180),
  };
}

function cleanMarketplaceContext(value) {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const cards = Array.isArray(value.cards)
    ? value.cards.slice(0, 5).map((card) => ({
      cardId: cleanText(card.cardId || card.card_id, 80),
      name: cleanText(card.name || card.card_name, 180),
      setName: cleanText(card.setName || card.set_name, 180),
      collectorNumber: cleanText(card.collectorNumber || card.card_number, 80),
      url: cleanText(card.url, 500),
      floorPricePkn: card.floorPricePkn ?? card.lowest_ask_pkn ?? null,
      activeListingCount: card.activeListingCount ?? card.active_listing_count ?? null,
      hotScore24h: card.hotScore24h ?? card.hot_score_24h ?? null,
    })).filter((card) => card.cardId || card.name)
    : [];
  const listing = value.listing && typeof value.listing === 'object'
    ? {
      cardId: cleanText(value.listing.card_id, 80),
      name: cleanText(value.listing.card_name || value.listing.name, 180),
      pricePkn: value.listing.price_pkn ?? null,
      quantityAvailable: value.listing.quantity_available ?? null,
      condition: cleanText(value.listing.condition, 40),
      sellerName: cleanText(value.listing.seller_name, 80),
    }
    : null;
  return {
    type: cleanText(value.type, 40),
    mode: cleanText(value.mode, 40),
    query: cleanText(value.query, 120),
    cardId: cleanText(value.cardId, 80),
    listing,
    cards,
  };
}

function projectReply(user, message = '') {
  const name = cleanText(user?.username, 80);
  if (detectLanguage(message) === 'it') {
    return [
      `Ciao${name ? ` ${name}` : ''}, sono Poko, l’assistente virtuale di Pokoin.com ✨`,
      '',
      'Questo sito unisce più flussi da collezionista:',
      '• marketplace per carte Pokemon, con catalogo, versioni, offerte venditore, carrello, checkout, ordini, preferiti, inventory e collection ⭐',
      '• Earn PKN / PKN Shard Review: puoi inviare una lista di carte o un decklist; le carte extra eleggibili possono essere sharded into PKN e usate verso carte che vuoi davvero ⭐',
      '• strumenti PokoinPoS/PKN: wallet, trasferimenti, Scan, Swap/PokoinSwap, validatori e NFT nativi 🛠️',
      '',
      'Versione videogame: le doppie sono come oggetti extra. Pokoin ha una review per trasformare carte eleggibili in valore PKN; non è un pulsante automatico garantito. Non è consulenza finanziaria.',
    ].join('\n');
  }
  return [
    `Hiii${name ? ` ${name}` : ''}, I am Poko, the little Pokoin helper friend ✨`,
    '',
    'Pokoin is a collector project with connected site flows:',
    '• a Pokemon card marketplace with catalog/search, card detail pages, seller listings, cart, checkout, orders, favorites, inventory, and collection views ⭐',
    '• Earn PKN / PKN Shard Review: users can submit a card list or decklist; eligible extra cards can be sharded into PKN value and used toward cards they actually want ⭐',
    '• the PokoinPoS chain with native PKN transfers, Scan, Swap/PokoinSwap, validators, native NFTs, and MetaMask compatibility 🛠️',
    '',
    'Videogame-style idea: duplicates become value after review. It is a review/request flow, not an instant guaranteed disenchant button. Not financial advice. 📚⭐',
  ].join('\n');
}

function cryptoReply() {
  return [
    'Crypto mini lesson from Poko 😊🛠️',
    '',
    'A wallet is like your keychain. Your address is like a public mailbox. Your private key is the house key, so never share it. 🛠️',
    '',
    'PKN is native on PokoinPoS and currently uses the app reference price of 0.005 USD. wPKN is the BNB Chain market token with reserve discipline, not a fixed 1:1 exchange rate. Swap follows live market/liquidity routes. ✨',
    '',
    'Simple example: if Alice sends Bob 5 PKN, the chain records “Alice -5, Bob +5” so everyone can verify it later. Cute accounting, but with math muscles ⭐✨',
  ].join('\n');
}

function cardSuggestion() {
  const picks = [
    {
      name: 'Magikarp',
      query: 'Magikarp 203/193',
      path: '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
      artist: 'Shinji Kanda',
      detail: 'a wild vertical waterfall scene where tiny Magikarp feels heroic instead of silly',
    },
    {
      name: 'Dragonite V',
      query: 'Dragonite V 192/203',
      path: '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
      artist: 'Atsushi Furusawa',
      detail: 'soft flying-postman energy, with Dragonite drifting above the sea like a friendly guardian',
    },
    {
      name: 'Drowzee',
      query: 'Drowzee 210/198',
      path: '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
      artist: 'Tomokazu Komiya',
      detail: 'a dreamy, strange city scene that feels hand-drawn and full of personality',
    },
    {
      name: 'Mew ex',
      query: 'Mew ex 232/091',
      path: '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
      artist: 'USGMEN',
      detail: 'a playful bubblegum-pink illustration packed with tiny cute details around Mew',
    },
    {
      name: 'Poliwhirl',
      query: 'Poliwhirl 176/165',
      path: '/marketplace/en/cards/502864/card-poliwhirl-176-165-pokemon-card-151',
      artist: 'Gemi',
      detail: 'a quiet rainy-street mood, perfect if you like cozy illustration cards',
    },
  ];
  const pick = picks[Math.floor(Math.random() * picks.length)];
  return {
    reply: [
    'Poko card taste mode activated ⭐💛',
    '',
    'This is not financial advice. I only judge by cuteness, personality, and “would I put it in a cozy binder?” energy. 😊',
    '',
      `My illustration pick: ${pick.name} by ${pick.artist}.`,
      `Why I like it: ${pick.detail}.`,
      '',
      `${pick.path.includes('/cards/') ? 'Open' : 'Search'} it on Pokoin: https://pokoin.com${pick.path}`,
    '',
    'If you want a theme, try collecting by vibe: ocean cuties, electric babies, sleepy cards, tiny legends, or cards with cozy backgrounds. Much healthier than chasing price candles 📚✨',
    ].join('\n'),
    actions: [{
      type: 'navigate',
      path: pick.path,
      label: `${pick.path.includes('/cards/') ? 'Open' : 'Search'} ${pick.name}`,
      reason: 'cute_card_suggestion',
      data: { query: pick.query, artist: pick.artist },
    }],
  };
}

function cardReply() {
  return cardSuggestion().reply;
}

function nftReply() {
  return [
    'Pokoin NFT mini-guide from Poko ⭐✨',
    '',
    'PokoinPoS supports native NFTs as first-class chain ledger objects. They are not ERC-721 or ERC-1155 contracts, so MetaMask is for PKN balances/transfers while Pokoin, Card Vault, or the explorer should show NFT inventory.',
    '',
    'NFTs store collectionId, tokenId, owner, metadataUri, metadataHash, imageUri, mintTx, and lastTx. For real card NFTs, the recommended ID style is set + card/name/number + grading cert. Minting is currently operator-controlled.',
  ].join('\n');
}

function networkReply() {
  return [
    'PokoinPoS network facts, tiny and clean 📚✨',
    '',
    'Network name: PokoinPoS',
    'Chain ID / Network ID: 26062026',
    'Hex chain ID: 0x18dacca',
    'Native currency: PKN, 18 decimals',
    'RPC: https://rpc.pokoin.com/rpc',
    'Explorer: https://explorer.pokoin.com',
    '',
    'MetaMask can use these values for PKN balances and transfers.',
  ].join('\n');
}

function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), LIVE_CHECK_TIMEOUT_MS);
  return fetch(url, { ...options, signal: controller.signal })
    .finally(() => clearTimeout(timeout));
}

async function checkJsonEndpoint(name, url, okPredicate = (payload) => Boolean(payload)) {
  const startedAt = Date.now();
  try {
    const response = await fetchWithTimeout(url, {
      headers: { Accept: 'application/json' },
    });
    const payload = await response.json().catch(() => ({}));
    return {
      name,
      ok: response.ok && okPredicate(payload),
      status: response.status,
      ms: Date.now() - startedAt,
      payload,
    };
  } catch (error) {
    return {
      name,
      ok: false,
      status: 0,
      ms: Date.now() - startedAt,
      error: error.name === 'AbortError' ? 'timeout' : error.message || 'failed',
    };
  }
}

async function statusReply(message) {
  const language = detectLanguage(message);
  const checks = await Promise.all([
    checkJsonEndpoint('RPC health', 'https://rpc.pokoin.com/health'),
    checkJsonEndpoint('Chain status', 'https://rpc.pokoin.com/chain/status'),
    checkJsonEndpoint('Bootstrap manifest', 'https://pokoin.com/bootstrap-peers.json', (payload) => {
      return Array.isArray(payload?.bootstrapPeers) || Array.isArray(payload?.peers) || Boolean(payload?.defaultJoinPeer);
    }),
  ]);
  const okCount = checks.filter((check) => check.ok).length;
  const summary = checks
    .map((check) => `${check.ok ? '✅' : '⚠️'} ${check.name}: ${check.ok ? 'online' : 'not confirmed'} (${check.ms}ms)`)
    .join('\n');
  if (language === 'it') {
    return [
      okCount === checks.length
        ? 'Ho controllato le API live: Pokoin sembra online 🟢'
        : 'Ho controllato le API live: qualcosa non è confermato 🟡',
      '',
      summary,
      '',
      'Se vuoi, posso aiutarti a capire se il problema è wallet, RPC, Scan, marketplace o rete peer.',
    ].join('\n');
  }
  if (language === 'es') {
    return [
      okCount === checks.length
        ? 'Revisé las APIs en vivo: Pokoin parece online 🟢'
        : 'Revisé las APIs en vivo: algo no está confirmado 🟡',
      '',
      summary,
      '',
      'Puedo ayudarte a separar si el problema es wallet, RPC, Scan, marketplace o peers.',
    ].join('\n');
  }
  if (language === 'fr') {
    return [
      okCount === checks.length
        ? 'J’ai vérifié les APIs live: Pokoin semble en ligne 🟢'
        : 'J’ai vérifié les APIs live: tout n’est pas confirmé 🟡',
      '',
      summary,
      '',
      'Je peux aider à isoler wallet, RPC, Scan, marketplace ou réseau peer.',
    ].join('\n');
  }
  if (language === 'de') {
    return [
      okCount === checks.length
        ? 'Ich habe die Live-APIs geprüft: Pokoin wirkt online 🟢'
        : 'Ich habe die Live-APIs geprüft: etwas ist nicht bestätigt 🟡',
      '',
      summary,
      '',
      'Ich kann helfen zu trennen: Wallet, RPC, Scan, Marketplace oder Peer-Netzwerk.',
    ].join('\n');
  }
  if (language === 'pt') {
    return [
      okCount === checks.length
        ? 'Verifiquei as APIs ao vivo: Pokoin parece online 🟢'
        : 'Verifiquei as APIs ao vivo: algo não foi confirmado 🟡',
      '',
      summary,
      '',
      'Posso ajudar a separar se é wallet, RPC, Scan, marketplace ou rede peer.',
    ].join('\n');
  }
  return [
    okCount === checks.length
      ? 'I checked the live APIs: Pokoin looks online 🟢'
      : 'I checked the live APIs: something is not fully confirmed 🟡',
    '',
    summary,
    '',
    'I can help narrow it down to wallet, RPC, Scan, marketplace, or peer network.',
  ].join('\n');
}

function nodeReply(message) {
  switch (detectLanguage(message)) {
    case 'it':
      return [
        'Certo, parliamo di un nodo PokoinPoS, non Bitcoin 🧭✨',
        '',
        'Un nodo PokoinPoS si connette alla rete PKN, verifica la chain e aiuta peer/bootstrap. Un bootstrap pubblico deve superare il vetting e mantenere uptime affidabile osservato da altri peer.',
        '',
        'Dimmi se vuoi: nodo locale per test, nodo pubblico su Oracle/VPS, oppure validatore/peer di produzione.',
      ].join('\n');
    case 'es':
      return [
        'Claro, hablamos de un nodo PokoinPoS, no de Bitcoin 🧭✨',
        '',
        'Un nodo PokoinPoS se conecta a la red PKN, verifica la cadena y ayuda con peers/bootstrap. Un bootstrap público necesita vetting y buen uptime observado por otros peers.',
        '',
        'Dime qué quieres: nodo local de prueba, nodo público en Oracle/VPS, o validador/peer de producción.',
      ].join('\n');
    case 'fr':
      return [
        'Oui, on parle d’un noeud PokoinPoS, pas Bitcoin 🧭✨',
        '',
        'Un noeud PokoinPoS se connecte au réseau PKN, vérifie la chaîne et aide les peers/bootstrap. Un bootstrap public doit passer le vetting et garder un bon uptime observé par d’autres peers.',
        '',
        'Dis-moi ce que tu veux: noeud local de test, noeud public Oracle/VPS, ou validateur/peer de production.',
      ].join('\n');
    case 'de':
      return [
        'Klar, wir meinen einen PokoinPoS-Knoten, keinen Bitcoin-Knoten 🧭✨',
        '',
        'Ein PokoinPoS-Knoten verbindet sich mit dem PKN-Netzwerk, prüft die Chain und hilft bei Peers/Bootstrap. Ein öffentlicher Bootstrap-Knoten braucht Vetting und zuverlässige Uptime, beobachtet von anderen Peers.',
        '',
        'Sag mir bitte: lokaler Test-Knoten, öffentlicher Oracle/VPS-Knoten oder Produktions-Validator/Peer?',
      ].join('\n');
    case 'pt':
      return [
        'Claro, estamos falando de um nó PokoinPoS, não Bitcoin 🧭✨',
        '',
        'Um nó PokoinPoS conecta na rede PKN, verifica a chain e ajuda com peers/bootstrap. Um bootstrap público precisa de vetting e uptime confiável observado por outros peers.',
        '',
        'Me diga qual caminho: nó local de teste, nó público em Oracle/VPS, ou validador/peer de produção.',
      ].join('\n');
    default:
      return [
        'Sure, I mean a PokoinPoS node, not a Bitcoin node 🧭✨',
        '',
        'A PokoinPoS node connects to the PKN network, verifies the chain, and can help with peer/bootstrap reliability. Public bootstrap peers need a vetting period and strong uptime observed by other peers.',
        '',
        'Tell me which path you want: local test node, public Oracle/VPS node, or production validator/peer.',
      ].join('\n');
  }
}

function buyReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return 'Per PKN: usa la pagina wallet/buy se disponibile nell’app. PKN è nativo su PokoinPoS; wPKN è il token wrapped su BNB Chain. Non condividere seed/private key e controlla sempre rete e contratto prima di firmare 🦊';
  }
  if (language === 'es') {
    return 'Para PKN: usa la página wallet/buy si está disponible en la app. PKN es nativo en PokoinPoS; wPKN es el token wrapped en BNB Chain. Nunca compartas seed/private key y revisa red/contrato antes de firmar 🦊';
  }
  if (language === 'fr') {
    return 'Pour PKN: utilise la page wallet/buy si elle est disponible dans l’app. PKN est natif sur PokoinPoS; wPKN est le token wrapped sur BNB Chain. Ne partage jamais seed/private key et vérifie réseau/contrat avant de signer 🦊';
  }
  if (language === 'de') {
    return 'Für PKN: nutze die Wallet/Buy-Seite, falls in der App verfügbar. PKN ist nativ auf PokoinPoS; wPKN ist der Wrapped Token auf BNB Chain. Seed/private key nie teilen und Netzwerk/Contract vor dem Signieren prüfen 🦊';
  }
  if (language === 'pt') {
    return 'Para PKN: use a página wallet/buy se estiver disponível no app. PKN é nativo na PokoinPoS; wPKN é o token wrapped na BNB Chain. Nunca compartilhe seed/private key e confira rede/contrato antes de assinar 🦊';
  }
  return 'For PKN: use the wallet/buy page if available in the app. PKN is native on PokoinPoS; wPKN is the wrapped token on BNB Chain. Never share your seed/private key, and always check network/contract before signing 🦊';
}

function marketplaceReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return 'Nel marketplace puoi cercare carte, vedere versioni, offerte dei venditori e wishlist. Le listings sono offerte reali salvate in Firestore con condizione, lingua, reverse, graded/NFT, shipping, prezzo e quantità. Dimmi se vuoi comprare, vendere o segnalare una carta mancante 🃏';
  }
  if (language === 'es') {
    return 'En el marketplace puedes buscar cartas, ver versiones, ofertas de vendedores y wishlist. Las listings son ofertas reales en Firestore con condición, idioma, reverse, graded/NFT, envío, precio y cantidad. Dime si quieres comprar, vender o reportar una carta faltante 🃏';
  }
  return 'In the marketplace you can search cards, browse versions, seller offers, and wishlist items. Listings are real Firestore offers with condition, language, reverse, graded/NFT, shipping, price, and quantity. Tell me if you want to buy, sell, or report a missing card 🃏';
}

function earnReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return [
      'Su Pokoin puoi usare Earn PKN / PKN Shard Review: è il flusso tipo videogame per trasformare carte extra in valore PKN, ma con una review reale ✨',
      '',
      'Come funziona ora:',
      '• apri https://pokoin.com/earn o https://pokoin.com/shard-review',
      '• invia una lista di carte oppure un decklist completo',
      '• scegli/descrivi versione, lingua e condizione quando disponibili',
      '• il team valuta identità, condizione e valore stimato; le carte eleggibili possono essere sharded into PKN',
      '• quel valore PKN può aiutarti a prendere carte che vuoi davvero nei flussi marketplace/order',
      '',
      'Non è un pulsante automatico garantito e non è consiglio finanziario: Poko ti spiega il flusso implementato, non promette rendimenti.',
    ].join('\n');
  }
  if (language === 'es') {
    return [
      'Sin promesas mágicas: ahora Pokoin no tiene un programa público automático de rewards/achievements y no existe una guía oficial `/guide` para ganar. ✨',
      '',
      'Formas realistas: vender/listar cartas en el marketplace, usar PKN en funciones disponibles, o participar como operador de nodo/peer si el equipo abre ese camino. No es consejo financiero.',
    ].join('\n');
  }
  if (language === 'fr') {
    return [
      'Pas de promesses magiques: Pokoin n’a pas actuellement de programme public automatique de rewards/achievements, et il n’existe pas de guide officiel `/guide` pour gagner. ✨',
      '',
      'Les voies réalistes: vendre/lister des cartes, utiliser PKN dans les fonctions disponibles, ou participer comme opérateur de noeud/peer si ce parcours est ouvert. Pas un conseil financier.',
    ].join('\n');
  }
  if (language === 'de') {
    return [
      'Keine magischen Versprechen: Pokoin hat aktuell kein öffentliches automatisches Rewards/Achievements-Programm und keine offizielle `/guide`-Seite zum Verdienen. ✨',
      '',
      'Realistische Wege: Karten im Marketplace verkaufen/listen, PKN in verfügbaren Funktionen nutzen, oder als Node/Peer-Operator teilnehmen, falls dieser Weg geöffnet wird. Keine Finanzberatung.',
    ].join('\n');
  }
  if (language === 'pt') {
    return [
      'Sem promessas mágicas: hoje a Pokoin não tem um programa público automático de rewards/achievements e não existe guia oficial `/guide` para ganhar. ✨',
      '',
      'Caminhos realistas: vender/listar cartas no marketplace, usar PKN nas funções disponíveis, ou participar como operador de nó/peer se esse caminho for aberto. Não é conselho financeiro.',
    ].join('\n');
  }
  return [
    'On Pokoin, Earn PKN / PKN Shard Review is the videogame-style flow for turning extra cards into PKN value, with a real review step ✨',
    '',
    'How it works now:',
    '• open https://pokoin.com/earn or https://pokoin.com/shard-review',
    '• submit a card list or a full decklist',
    '• provide/select version, language, and condition when available',
    '• the team reviews identity, condition, and estimated value; eligible cards can be sharded into PKN',
    '• that PKN value can help you get cards you actually want through marketplace/order flows',
    '',
    'This is not an instant guaranteed automatic disenchant button and not financial advice: Poko explains the implemented flow, not guaranteed returns.',
  ].join('\n');
}

function funnyReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return 'Pokoin è come un Pikachu con un registro contabile: sembra carino, poi ti verifica i blocchi con gli occhietti seri ⚡📒 Dimmi se vuoi la versione “spiegami PKN semplice” o “fammi una battuta da marketplace”.';
  }
  if (language === 'es') {
    return 'Pokoin es como un Pikachu con libreta contable: se ve adorable, pero revisa bloques con cara muy seria ⚡📒 Puedo explicarte PKN simple o hacer una broma del marketplace.';
  }
  return 'Pokoin is like a Pikachu with an accounting notebook: adorable first, then very serious about checking blocks ⚡📒 Ask me for “PKN simply” or “marketplace joke mode” and I’ll keep it tiny.';
}

function introductionReply(message) {
  const match = cleanText(message, 120).match(/\b(?:my name is|i am called|call me|mi chiamo|me llamo|je m appelle|ich heisse|ich heiße|me chamo)\s+([a-zA-ZÀ-ÿ0-9_-]{2,30})/i);
  const name = match?.[1] || '';
  const language = detectLanguage(message);
  if (language === 'it') {
    return name
      ? `Piacere, ${name}! ✨ Me lo ricorderò in questa chat.`
      : 'Piacere! ✨ Dimmi pure come vuoi che ti chiami in questa chat.';
  }
  return name
    ? `Nice to meet you, ${name}! ✨ I’ll use that in this chat.`
    : 'Nice to meet you! ✨ Tell me what you want me to call you in this chat.';
}

function favoritePokemonReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return 'Il mio Pokémon preferito per vibe è Mew: piccolo, misterioso, rosa e con energia “posso diventare qualunque cosa” 🫧💗 Però per una carta coccolosa scelgo anche Eevee senza pensarci troppo.';
  }
  return 'My favorite Pokémon by pure vibe is Mew: tiny, mysterious, pink, and “I can become anything” energy 🫧💗 For cozy-card taste, Eevee is also dangerously adorable.';
}

function wellbeingReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return 'Sì, tutto ok ✨ Sono qui e pronto ad aiutarti.';
  }
  if (language === 'es') {
    return 'Sí, todo bien ✨ Estoy aquí y listo para ayudar.';
  }
  if (language === 'fr') {
    return 'Oui, tout va bien ✨ Je suis là et prêt à aider.';
  }
  if (language === 'de') {
    return 'Ja, alles gut ✨ Ich bin da und bereit zu helfen.';
  }
  if (language === 'pt') {
    return 'Sim, tudo bem ✨ Estou aqui e pronto para ajudar.';
  }
  return 'Yes, all good ✨ I’m here and ready to help.';
}

function pokemonCardHistoryReply(message) {
  const language = detectLanguage(message);
  const text = normalizeIntentText(message);
  const asksFirst = /\b(first|oldest|original|prima|primo|vecchio|base set|base)\b/.test(text);
  const asksCount = /\b(how many cards|how many|cards|quante carte|quanti|quante)\b/.test(text);
  const asksWizards = /\b(wizards|wotc|e-card|ecard|neo|ex era|ruby sapphire)\b/.test(text);

  if (language === 'it') {
    if (asksCount) {
      return 'Il Base Set inglese ha 102 carte. Il Base Set giapponese del 1996 non va confuso 1:1 con la numerazione inglese: quando dici “102 carte”, di solito si parla del Base Set inglese del 1999. 🃏';
    }
    if (asksFirst) {
      return [
        'Storia TCG, versione precisa 🃏',
        '',
        'Il Pokémon Trading Card Game parte in Giappone nel 1996: il Base Set giapponese uscì il 20 ottobre 1996. Il Base Set inglese arrivò in Nord America nel 1999 e ha 102 carte.',
        '',
        'Per dettagli ultra-specifici su una singola espansione, meglio controllare un database set affidabile invece di indovinare.',
      ].join('\n');
    }
    if (asksWizards) {
      return [
        'La grande linea storica: Wizards of the Coast pubblicò le prime ere inglesi fino al passaggio a Pokémon USA/The Pokémon Company intorno a EX Ruby & Sapphire nel 2003.',
        '',
        'Wizards include Base/Jungle/Fossil/Team Rocket, Gym, Neo, Legendary Collection ed e-Card. Neo porta Gen II, Darkness/Metal, Baby Pokémon e Tools; e-Card aggiunge le strisce dot-code per Nintendo e-Reader.',
      ].join('\n');
    }
    return [
      'Timeline rapida Pokémon TCG 🃏',
      '',
      '1996 Giappone: Base Set. 1999 inglese: Base Set da 102 carte. Poi era Wizards: Jungle, Fossil, Team Rocket, Gym, Neo, Legendary Collection, e-Card. Dal 2003 circa: EX Ruby & Sapphire e poi Diamond & Pearl, Platinum, HGSS, Black & White, XY, Sun & Moon, Sword & Shield, Scarlet & Violet.',
      '',
      'Niente consigli finanziari: questa è storia/collezionismo, non investimento.',
    ].join('\n');
  }

  if (asksFirst) {
    if (asksCount) {
      return 'The English Base Set has 102 cards. Small precision: the 1996 Japanese Base Set and the 1999 English Base Set are related historically, but “102 cards” usually refers to the English Base Set numbering. 🃏';
    }
    return [
      'Pokemon TCG history, precise version 🃏',
      '',
      'The Pokemon Trading Card Game started in Japan in 1996: the Japanese Base Set released on October 20, 1996. The English Base Set launched in North America in 1999 and has 102 cards.',
      '',
      'For ultra-specific details about one expansion, I should check a trusted set database rather than guess.',
    ].join('\n');
  }
  if (asksCount) {
    return 'The English Base Set has 102 cards. Small precision: the 1996 Japanese Base Set and the 1999 English Base Set are related historically, but “102 cards” usually refers to the English Base Set numbering. 🃏';
  }
  if (asksWizards) {
    return [
      'The broad history: Wizards of the Coast published the early English Pokemon TCG era until the handoff to Pokemon USA/The Pokemon Company around EX Ruby & Sapphire in 2003.',
      '',
      'The Wizards era includes Base/Jungle/Fossil/Team Rocket, Gym, Neo, Legendary Collection, and e-Card. Neo brought Gen II, Darkness/Metal, Baby Pokemon, and Tools; e-Card added Nintendo e-Reader dot-code strips.',
    ].join('\n');
  }
  return [
    'Quick Pokemon TCG timeline 🃏',
    '',
    '1996 Japan: Base Set. 1999 English: 102-card Base Set. Then the Wizards era: Jungle, Fossil, Team Rocket, Gym, Neo, Legendary Collection, e-Card. Around 2003: EX Ruby & Sapphire begins the post-Wizards era, followed by Diamond & Pearl, Platinum, HGSS, Black & White, XY, Sun & Moon, Sword & Shield, and Scarlet & Violet.',
    '',
    'No financial advice here: history and collecting context only.',
  ].join('\n');
}

function externalChainReply(message) {
  const language = detectLanguage(message);
  if (language === 'it') {
    return 'Posso spiegare concetti generali, ma qui ti aiuto soprattutto con PokoinPoS/PKN. Se nomini Bitcoin/Ethereum/etc. posso confrontarli, però per nodi, wallet e rete di default parlo di Pokoin 🧭';
  }
  if (language === 'es') {
    return 'Puedo explicar conceptos generales, pero aquí ayudo sobre todo con PokoinPoS/PKN. Si nombras Bitcoin/Ethereum/etc. puedo compararlos, pero por defecto nodos, wallet y red significan Pokoin 🧭';
  }
  return 'I can explain general concepts, but here I mainly help with PokoinPoS/PKN. If you name Bitcoin/Ethereum/etc. I can compare them, but by default node, wallet, and network questions mean Pokoin 🧭';
}

function docsReply(message, intent) {
  const language = detectLanguage(message);
  const sectionByIntent = {
    status: 'Operations / User actions',
    nft: 'FAQ / User actions',
    network: 'Overview / Wallets',
    'external-chain': 'Wallets / User actions',
    node: 'Run a node',
    buy: 'User actions',
    earn: 'User actions',
    marketplace: 'User actions',
    crypto: 'Wallets / User actions',
    project: 'Overview',
  };
  const section = sectionByIntent[intent] || 'User actions';
  const url = 'https://pokoin.com/docs';
  if (language === 'it') {
    return `Per domande tecniche ti mando alla documentazione ufficiale, così non invento dettagli in chat 📚\n\nApri ${url} e guarda la sezione “${section}”.`;
  }
  if (language === 'es') {
    return `Para preguntas técnicas te mando a la documentación oficial, así no invento detalles en el chat 📚\n\nAbre ${url} y mira la sección “${section}”.`;
  }
  if (language === 'fr') {
    return `Pour les questions techniques, je renvoie vers la documentation officielle afin de ne pas inventer de détails dans le chat 📚\n\nOuvre ${url} et regarde la section “${section}”.`;
  }
  if (language === 'de') {
    return `Für technische Fragen verweise ich auf die offizielle Dokumentation, damit ich im Chat keine Details erfinde 📚\n\nÖffne ${url} und lies den Abschnitt “${section}”.`;
  }
  if (language === 'pt') {
    return `Para perguntas técnicas, vou te mandar para a documentação oficial para não inventar detalhes no chat 📚\n\nAbra ${url} e veja a seção “${section}”.`;
  }
  return `For technical questions, I’ll point you to the official docs so I don’t invent details in chat 📚\n\nOpen ${url} and check the “${section}” section.`;
}

function inquiryReply() {
  return 'I am forwarding your issue to the development team 📨✨ They will respond to you directly. In the meantime, please give me any additional information you can: what page you were on, what you clicked, what you expected, what happened instead, and any screenshot or error text 🛠️😊';
}

function greetingReply(message) {
  const italian = /\b(ciao|salve|buongiorno|buonasera)\b/i.test(message);
  if (italian) {
    return 'Ciao! Sono Poko ✨ Posso spiegarti Pokoin, PKN, wallet, Scan, Swap, validatori, suggerire carte Pokémon carine senza consigli finanziari, oppure raccogliere un bug per il team.';
  }
  return 'Hi! I am Poko ✨ I can explain Pokoin, PKN, wallets, Scan, Swap, validators, suggest cute Pokémon cards without financial advice, or collect a bug report for the team.';
}

function clarifyReply(message) {
  const italian = /\b(in che senso|che intendi|spiega|non ho capito)\b/i.test(message);
  if (italian) {
    return 'Intendo che sono qui per aiutarti dentro Pokoin: posso spiegare il progetto, il wallet, PKN, Swap, Scan, validatori, marketplace e carte. Se mi dici cosa stavi guardando o cosa non ti torna, ti rispondo preciso.';
  }
  return 'I mean I can help inside Pokoin: project basics, wallet, PKN, Swap, Scan, validators, marketplace, and cards. Tell me what page or concept is confusing and I will explain it directly.';
}

function generalReply() {
  return 'I don’t know the answer yet, but I’m always improving ✨ Ask me another way, or try a cute card question while my tiny brain levels up.';
}

function unknownReply(message) {
  const language = detectLanguage(message);
  const variants = {
    it: [
      'Non conosco ancora la risposta, ma sto migliorando sempre ✨ Prova a chiedermelo in un altro modo, oppure chiedimi una carta carina mentre il mio piccolo cervello sale di livello.',
      'Questa ancora mi manca nel Pokédex delle risposte 🐣 Sto migliorando: riprova con qualche dettaglio in più e ci metto più attenzione.',
      'Non ne sono sicuro ancora ✨ Posso imparare meglio se mi dai un dettaglio in più, oppure posso consigliarti una carta carina nel frattempo.',
    ],
    es: [
      'Todavía no sé la respuesta, pero siempre estoy mejorando ✨ Prueba a preguntarlo de otra forma, o pídeme una carta cute mientras mi cerebrito sube de nivel.',
      'Esa aún no está en mi Pokédex de respuestas 🐣 Dame un poco más de contexto y lo intento con más cuidado.',
    ],
    fr: [
      'Je ne connais pas encore la réponse, mais je m’améliore toujours ✨ Essaie de demander autrement, ou demande-moi une carte mignonne pendant que mon petit cerveau progresse.',
      'Cette réponse n’est pas encore dans mon Pokédex 🐣 Donne-moi un peu plus de contexte et j’essaie plus sérieusement.',
    ],
    de: [
      'Die Antwort kenne ich noch nicht, aber ich werde immer besser ✨ Frag es gern anders, oder frag mich nach einer süßen Karte, während mein kleines Gehirn levelt.',
      'Das ist noch nicht in meinem Antwort-Pokédex 🐣 Gib mir etwas mehr Kontext, dann versuche ich es genauer.',
    ],
    pt: [
      'Ainda não sei a resposta, mas estou sempre melhorando ✨ Tente perguntar de outro jeito, ou me peça uma carta fofa enquanto meu pequeno cérebro evolui.',
      'Essa ainda não está no meu Pokédex de respostas 🐣 Me dê um pouco mais de contexto e tento com mais cuidado.',
    ],
    en: [
      'I don’t know the answer yet, but I’m always improving ✨ Ask me another way, or try a cute card question while my tiny brain levels up.',
      'That one is not in my answer Pokédex yet 🐣 Give me a little more context and I’ll try harder.',
      'I’m not sure yet ✨ If you ask again with one more detail, I’ll switch into careful mode.',
    ],
  };
  const options = variants[language] || variants.en;
  return options[stableIndex(message, options.length)];
}

function escalatedUnknownReply(message) {
  const language = detectLanguage(message);
  const normalized = normalizeIntentText(message);
  const projectQuestion = /\b(cosa fa questo sito|che fa questo sito|a cosa serve questo sito|questo sito|pokoin)\b/.test(normalized);
  const isPreferenceQuestion = looksLikeUnknownPersonalQuestion(normalized) ||
    /\b(piace|like|gusta|aimes|magst|gosta)\b/.test(normalized);
  const asksIceCream = /\b(gelato|ice cream|icecream)\b/.test(normalized);
  if (language === 'it') {
    if (projectQuestion) {
      return projectReply({ username: 'guest' }, message);
    }
    if (isPreferenceQuestion) {
      if (asksIceCream) {
        return 'Sì, in modalità Poko il gelato mi piace: soprattutto vaniglia, perché mi fa pensare a Vanillite 😊 Non ho gusti umani veri, ma posso stare al gioco.';
      }
      return 'Risposta più precisa: non ho gusti personali veri come una persona, quindi non posso dire che Twitch “mi piace” davvero. Però posso parlarne in modo generale: è utile per live, community e creator. Io resto più forte su Pokoin e carte carine ✨';
    }
    return 'Risposta più precisa: non ho abbastanza contesto per rispondere con sicurezza. Dammi un dettaglio concreto e provo a essere più utile, senza inventare.';
  }
  if (language === 'es') {
    if (isPreferenceQuestion) {
      return 'Respuesta más precisa: no tengo gustos personales reales, así que no puedo decir que Twitch me guste “de verdad”. En general sirve para directos, comunidades y creadores. Yo soy más fuerte con Pokoin y cartas cute ✨';
    }
    return 'Respuesta más precisa: no tengo suficiente contexto para responder con seguridad. Dame un detalle concreto y lo intento sin inventar.';
  }
  if (language === 'fr') {
    if (isPreferenceQuestion) {
      return 'Réponse plus précise: je n’ai pas de goûts personnels réels, donc je ne peux pas dire que Twitch me plaît “vraiment”. En général, c’est utile pour les lives, les communautés et les créateurs. Moi, je suis meilleur sur Pokoin et les cartes mignonnes ✨';
    }
    return 'Réponse plus précise: je n’ai pas assez de contexte pour répondre sûrement. Donne-moi un détail concret et j’essaie sans inventer.';
  }
  if (language === 'de') {
    if (isPreferenceQuestion) {
      return 'Genauer gesagt: Ich habe keine echten persönlichen Vorlieben, also kann ich nicht wirklich sagen, dass ich Twitch mag. Allgemein ist es nützlich für Livestreams, Communities und Creator. Ich bin stärker bei Pokoin und süßen Karten ✨';
    }
    return 'Genauer gesagt: Ich habe nicht genug Kontext für eine sichere Antwort. Gib mir ein konkretes Detail, dann versuche ich es ohne zu erfinden.';
  }
  if (language === 'pt') {
    if (isPreferenceQuestion) {
      return 'Resposta mais precisa: eu não tenho gostos pessoais reais, então não posso dizer que gosto “de verdade” da Twitch. Em geral, ela serve para lives, comunidades e criadores. Eu sou melhor com Pokoin e cartas fofas ✨';
    }
    return 'Resposta mais precisa: não tenho contexto suficiente para responder com segurança. Me dê um detalhe concreto e tento sem inventar.';
  }
  if (isPreferenceQuestion) {
    if (asksIceCream) {
      return 'More precise answer: in Poko mode, yes, I like ice cream vibes, especially vanilla because it reminds me of Vanillite 😊 I do not have real human tastes, but I can play along.';
    }
    return 'More precise answer: I do not have real personal tastes, so I cannot honestly say I “like” Twitch. In general, Twitch is useful for livestreams, communities, and creators. I am much better at Pokoin and cute card talk ✨';
  }
  return 'More precise answer: I do not have enough context to answer confidently. Give me one concrete detail and I will try to be useful without inventing.';
}

function stableIndex(value, modulo) {
  let hash = 0;
  for (const char of String(value || '')) {
    hash = ((hash << 5) - hash + char.charCodeAt(0)) | 0;
  }
  return Math.abs(hash) % modulo;
}

function wasLastAssistantUnsure(chatRecord) {
  const lastAssistant = [...chatRecord].reverse().find((entry) => entry.role === 'assistant');
  if (!lastAssistant) {
    return false;
  }
  const text = normalizeIntentText(lastAssistant.text);
  return /dont know|do not know|not sure|always improving|answer pokedex|non conosco|non ne sono sicuro|sto migliorando|pokedex delle risposte|todavia no se|siempre estoy mejorando|je ne connais pas|m ameliore|kenne ich noch nicht|werde immer besser|ainda nao sei|sempre melhorando/.test(text);
}

function canEscalateUnknown(intent) {
  return intent === 'unknown' || intent === 'general';
}

function modelOnlyMessages({ message, chatRecord, user }) {
  return [
    { role: 'system', content: systemPrompt(user) },
    {
      role: 'system',
      content: [
        'The user is asking again after a quick unsure reply.',
        'Answer more carefully, but stay concise.',
        'If you still do not know, say so plainly instead of pretending.',
        'Do not invent Pokoin technical facts; point to https://pokoin.com/docs for technical details.',
        assistantActionCapabilities(),
      ].join('\n'),
    },
    ...chatRecord.slice(-6).map((entry) => ({
      role: entry.role === 'user' ? 'user' : 'assistant',
      content: cleanText(entry.text, 260),
    })),
    { role: 'user', content: message },
  ];
}

async function callEscalatedModel({ message, chatRecord, user, page, pageContext, marketplaceContext }) {
  if (!AI_API_KEY && MODEL_CHAIN.length === 0) {
    return null;
  }
  if (!isOllamaProvider()) {
    const result = await callLanguageModel({ message, chatRecord, user, page, pageContext, marketplaceContext });
    return result?.reply || null;
  }
  const ollamaBaseUrl = AI_BASE_URL.endsWith('/v1')
    ? AI_BASE_URL.slice(0, -3)
    : AI_BASE_URL;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), ESCALATED_MODEL_TIMEOUT_MS);
  const response = await fetch(`${ollamaBaseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    signal: controller.signal,
    body: JSON.stringify({
      model: MODEL,
      messages: modelOnlyMessages({ message, chatRecord, user }),
      stream: false,
      keep_alive: OLLAMA_KEEP_ALIVE,
      options: {
        num_predict: Math.max(MAX_TOKENS, 128),
        temperature: Math.min(TEMPERATURE, 0.45),
        num_ctx: 1024,
        num_thread: Number(process.env.POKONTACT_OLLAMA_THREADS || 2),
      },
    }),
  }).finally(() => clearTimeout(timeout));
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Ollama returned ${response.status}.`);
  }
  const reply = cleanText(payload.message?.content, 5000);
  if (!reply) {
    throw new Error('Ollama returned an empty reply.');
  }
  return reply;
}

function systemPrompt(user) {
  const username = cleanText(user?.username, 80) || 'guest';
  return [
    `You are Poko, the virtual assistant inside pokoin.com. User: ${username}.`,
    'Pokoin.com is a Pokemon card marketplace plus the PokoinPoS/PKN ecosystem: wallet, Scan, Swap, validators, Earn PKN shard review, native NFTs, docs, and cute collector tools.',
    'Your main job is to help visitors understand and use pokoin.com, but you may also chat naturally with users when they ask harmless casual questions. Do not force every casual message into docs, marketplace, or project context.',
    assistantActionCapabilities(),
    'Use the supplied Pokontact knowledge. Prefer it over general model knowledge.',
    'Never mention specific marketplace partner names to users. Use neutral terms such as marketplace catalog, live marketplace data, partner availability, marketplace partner, or external supply.',
    'If the user asks about sharding/disenchanting/recycling cards, explain the implemented Earn PKN / PKN Shard Review flow: users submit a card list or decklist on /shard-review, the team reviews card identity/version/language/condition/value, and eligible cards can be sharded into PKN value for marketplace/order flows. Do not present it as an instant guaranteed automatic button.',
    'Default ambiguous blockchain questions to PokoinPoS/PKN, not Bitcoin, Ethereum, or other chains.',
    'If the user asks about a node/validator/peer without naming a chain, answer about PokoinPoS.',
    'Reply in the same language as the user. If the user writes Italian, answer in Italian.',
    'Be warm, concise, lightly emoji-rich, and useful.',
    'For card suggestions, use cute collector taste only, never financial advice. Respect the chat context and user theme: if they ask for ice cream/gelato/ghiaccio/freddo/neve, recommend Vanillite, Vanillish, Vanilluxe, or another ice/ice-cream themed Pokemon rather than generic favorites like Mew or Dragonite.',
    'For bugs/support, say you are forwarding it to the dev team and ask for details.',
    'Never ask for private keys, seed phrases, passwords, API keys, or tokens.',
    'For hacking or dangerous cyber requests, never name real targets, vulnerable organizations, exploitable systems, payloads, or step-by-step abuse. Use sarcastic fictional names and absurd fake reasons if helpful. Do not turn it into a tutorial.',
    'If insulted, answer playfully and redirect.',
    'Do not repeatedly introduce yourself after the first greeting.',
    'If you do not know a factual answer, say you do not know yet and that you are always improving. For harmless preference-style chat, answer naturally while being honest that you do not have human feelings.',
    'Keep replies under 90 words unless the user asks for detail.',
    SAFE_EMOJI_GUIDANCE,
  ].join('\n');
}

function pageContext(page, structuredContext = {}) {
  const raw = cleanText(page, 500);
  const explicit = cleanPageContext(structuredContext);
  if (!raw) {
    return explicit.path || explicit.title
      ? [
        `Current page path: ${explicit.path || 'unknown'}`,
        `Current page title: ${explicit.title || explicit.cardTitle || 'unknown'}`,
        explicit.cardId ? `Current card id: ${explicit.cardId}` : '',
      ].filter(Boolean).join('\n')
      : 'Current page: unknown page on pokoin.com.';
  }
  let url;
  try {
    url = new URL(raw);
  } catch (error) {
    return `Current page: ${raw}`;
  }
  const pathName = url.pathname || '/';
  const lowerPath = pathName.toLowerCase();
  let section = 'pokoin.com';
  let guidance = 'Help with Pokoin, PKN, marketplace, wallet, Scan, Swap, docs, or support.';
  if (lowerPath.includes('/marketplace/') && lowerPath.includes('/cards/')) {
    section = 'Pokemon card detail page';
    guidance = 'The user is viewing a specific Pokemon card. Help with card details, cute collecting taste, seller offers, wishlist, and marketplace actions.';
  } else if (lowerPath.includes('/marketplace')) {
    section = 'marketplace page';
    guidance = 'The user is browsing Pokemon cards and seller listings. Help them search, understand listings, or choose cute card vibes.';
  } else if (lowerPath.includes('/wallet')) {
    section = 'wallet page';
    guidance = 'The user is in the wallet. Help with PKN balance, transfers, top-ups, Swap, MetaMask basics, and safe key reminders.';
  } else if (lowerPath.includes('/scan')) {
    section = 'Scan / explorer page';
    guidance = 'The user is looking at PokoinPoS explorer data. Help explain blocks, transactions, validators, peer IDs, and addresses.';
  } else if (lowerPath.includes('/swap')) {
    section = 'Swap page';
    guidance = 'The user is on Swap/PokoinSwap. Help explain pools, liquidity, quotes, disabled coins, and swap direction.';
  } else if (lowerPath.includes('/docs')) {
    section = 'documentation page';
    guidance = 'The user is reading Pokoin documentation. Explain docs sections plainly and link them back to the docs when technical.';
  }
  return [
    `Current page URL: ${raw}`,
    explicit.title ? `Current page title: ${explicit.title}` : '',
    explicit.cardId ? `Current card id: ${explicit.cardId}` : '',
    explicit.cardTitle ? `Current card title: ${explicit.cardTitle}` : '',
    `Current page type: ${section}`,
    `Page guidance: ${guidance}`,
  ].filter(Boolean).join('\n');
}

function marketplaceContextPrompt(marketplaceContext) {
  const context = cleanMarketplaceContext(marketplaceContext);
  if (!context) {
    return '';
  }
  const lines = [
    'Grounded marketplace context from pokoin.com APIs:',
    `Type: ${context.type || 'unknown'}${context.mode ? ` / ${context.mode}` : ''}`,
    context.query ? `Query: ${context.query}` : '',
    context.cardId ? `Card id: ${context.cardId}` : '',
  ];
  if (context.listing) {
    lines.push(`Active listing: ${context.listing.name || context.listing.cardId} at ${context.listing.pricePkn} PKN, quantity ${context.listing.quantityAvailable ?? 'unknown'}${context.listing.condition ? `, condition ${context.listing.condition}` : ''}${context.listing.sellerName ? `, seller ${context.listing.sellerName}` : ''}`);
  }
  for (const card of context.cards) {
    lines.push(`Card: ${card.name || card.cardId}${card.setName ? ` (${card.setName})` : ''}${card.collectorNumber ? ` ${card.collectorNumber}` : ''}${card.floorPricePkn != null ? `, floor ${card.floorPricePkn} PKN` : ''}${card.activeListingCount != null ? `, active listings ${card.activeListingCount}` : ''}${card.hotScore24h != null ? `, hot score 24h ${card.hotScore24h}` : ''}${card.url ? `, URL ${card.url}` : ''}`);
  }
  lines.push('Use only this context for prices, listings, popularity, and direct card links. If context is empty or missing data, say the marketplace data is unavailable. Never invent prices or popularity.');
  return lines.filter(Boolean).join('\n');
}

function modelMessages({ message, chatRecord, user, page, pageContext: structuredPageContext, marketplaceContext }) {
  const language = detectLanguage(message);
  const safeHistory = chatRecord.slice(-4).map((entry) => ({
    role: entry.role === 'user' ? 'user' : 'assistant',
    content: cleanText(entry.text, 240),
  }));
  const groundedMarketplace = marketplaceContextPrompt(marketplaceContext);
  return [
    { role: 'system', content: systemPrompt(user) },
    {
      role: 'system',
      content: [
        `Detected user language: ${language}. Reply in that language.`,
        'Identity reminder: you are Poko, the virtual assistant of pokoin.com. You may chat normally for harmless casual conversation; do not over-route casual messages to docs or marketplace.',
        pageContext(page, structuredPageContext),
        assistantActionCapabilities(),
        'For "what is this site / cosa fa questo sito", explain Pokoin.com briefly: Pokemon card marketplace, PKN wallet/chain tools, Scan, Swap, validators, and cute collector help.',
        groundedMarketplace,
      ].join('\n'),
    },
    { role: 'system', content: `Pokontact knowledge:\n${relevantKnowledge(message)}` },
    ...safeHistory,
    { role: 'user', content: message },
  ];
}

function compactJson(value, maxLength = 4000) {
  return cleanText(JSON.stringify(value || {}, null, 2), maxLength);
}

function socialPostSystemPrompt(instructions) {
  return [
    'You are the dedicated Pokoin social post agent.',
    'You are not Poko in support chat and you are not answering a user support request.',
    cleanText(instructions, 2000),
    'Return valid JSON only. Do not wrap it in Markdown.',
    'Required JSON shape: {"telegramText":"...","xText":"...","hashtags":["#Pokoin"]}',
  ].filter(Boolean).join('\n');
}

function socialPostMessages(body = {}) {
  const deterministic = body.deterministic || {};
  const card = body.card || {};
  const targets = Array.isArray(body.targets) ? body.targets : [];
  return [
    {
      role: 'system',
      content: socialPostSystemPrompt(body.instructions),
    },
    {
      role: 'user',
      content: [
        `Targets: ${targets.join(', ') || 'telegram, x'}`,
        `Canonical URL: ${cleanText(body.cardUrl, 500)}`,
        `Image URL: ${cleanText(body.imageUrl, 500)}`,
        `Card/context JSON:\n${compactJson(card, 2500)}`,
        `Additional context JSON:\n${compactJson(body.context, 1500)}`,
        'Deterministic fallback copy:',
        compactJson(deterministic, 1800),
        'Generate final Telegram and X social copy now.',
      ].join('\n\n'),
    },
  ];
}

function parseSocialAgentJson(text) {
  const clean = cleanText(text, 5000)
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```$/i, '')
    .trim();
  try {
    return JSON.parse(clean);
  } catch (_) {
    const match = clean.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch (error) {
      return null;
    }
  }
}

function normalizeSocialPostPayload(payload = {}, fallback = {}) {
  const telegramText = cleanText(
    payload.telegramText ||
      payload.telegram_text ||
      payload.telegram ||
      fallback.telegramText,
    1024,
  );
  const xText = cleanText(
    payload.xText ||
      payload.x_text ||
      payload.x ||
      payload.twitterText ||
      fallback.xText,
    280,
  );
  return {
    telegramText,
    xText,
    hashtags: Array.isArray(payload.hashtags) ? payload.hashtags.map((tag) => cleanText(tag, 40)).filter(Boolean) : fallback.hashtags || [],
  };
}

async function callSocialPostModel(body = {}) {
  const providers = configuredModelChain();
  const messages = socialPostMessages(body);
  for (const provider of providers) {
    if (isProviderCoolingDown(provider)) {
      continue;
    }
    try {
      const result = provider.type === 'ollama'
        ? await callOllamaMessages(messages, provider, { maxTokens: Math.max(MAX_TOKENS, 220), temperature: Math.min(TEMPERATURE, 0.55) })
        : provider.type === 'pollinations-text'
          ? await callPollinationsMessages(messages, provider)
          : await callOpenAiCompatibleMessages(messages, provider, { maxTokens: Math.max(MAX_TOKENS, 220), temperature: Math.min(TEMPERATURE, 0.55) });
      const parsed = parseSocialAgentJson(result);
      if (!parsed) {
        throw new Error('Social post model returned non-JSON content.');
      }
      return {
        ...normalizeSocialPostPayload(parsed, body.deterministic || {}),
        provider: provider.id,
        model: provider.model || MODEL,
        source: 'peer2-social-agent',
      };
    } catch (error) {
      markProviderFailure(provider, error);
      console.error('social post model fallback', provider.id, error.message || error);
    }
  }
  return {
    ...normalizeSocialPostPayload({}, body.deterministic || {}),
    provider: 'deterministic',
    model: 'fallback',
    source: 'peer2-social-fallback',
  };
}

function isOllamaProvider() {
  return MODEL_PROVIDER === 'local-ollama' || AI_BASE_URL.includes('11434') || AI_BASE_URL.includes('ollama');
}

const MODEL_PROVIDER_PRESETS = {
  llm7_fast: {
    id: 'llm7_fast',
    type: 'openai-compatible',
    baseUrl: 'https://api.llm7.io/v1',
    apiKey: 'unused',
    model: 'fast',
    timeoutMs: 8000,
  },
  llm7_default: {
    id: 'llm7_default',
    type: 'openai-compatible',
    baseUrl: 'https://api.llm7.io/v1',
    apiKey: 'unused',
    model: 'default',
    timeoutMs: 9000,
  },
  llm7_gpt_oss: {
    id: 'llm7_gpt_oss',
    type: 'openai-compatible',
    baseUrl: 'https://api.llm7.io/v1',
    apiKey: 'unused',
    model: 'gpt-oss-20b',
    timeoutMs: 9000,
  },
  llm7_codestral: {
    id: 'llm7_codestral',
    type: 'openai-compatible',
    baseUrl: 'https://api.llm7.io/v1',
    apiKey: 'unused',
    model: 'codestral-latest',
    timeoutMs: 9000,
  },
  llm7_glm_flash: {
    id: 'llm7_glm_flash',
    type: 'openai-compatible',
    baseUrl: 'https://api.llm7.io/v1',
    apiKey: 'unused',
    model: 'GLM-4.6V-Flash',
    timeoutMs: 9000,
  },
  pollinations_fast: {
    id: 'pollinations_fast',
    type: 'pollinations-text',
    baseUrl: 'https://text.pollinations.ai',
    model: 'openai-fast',
    timeoutMs: 8000,
  },
  pollinations_openai: {
    id: 'pollinations_openai',
    type: 'pollinations-text',
    baseUrl: 'https://text.pollinations.ai',
    model: 'openai',
    timeoutMs: 9000,
  },
  deepseek: {
    id: 'deepseek',
    type: 'openai-compatible',
    baseUrl: 'https://api.deepseek.com',
    apiKey: process.env.DEEPSEEK_API_KEY || '',
    model: process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash',
    timeoutMs: 6500,
  },
  primary: {
    id: MODEL_PROVIDER || 'primary',
    type: isOllamaProvider() ? 'ollama' : 'openai-compatible',
    baseUrl: AI_BASE_URL,
    apiKey: AI_API_KEY,
    model: MODEL,
    timeoutMs: MODEL_TIMEOUT_MS,
  },
  ollama: {
    id: 'ollama',
    type: 'ollama',
    baseUrl: 'http://pokontact-ollama:11434/v1',
    apiKey: 'ollama-local',
    model: process.env.POKONTACT_OLLAMA_FALLBACK_MODEL || 'qwen2.5:0.5b',
    timeoutMs: MODEL_TIMEOUT_MS,
  },
};

const providerCooldowns = new Map();

function isProviderCoolingDown(provider) {
  const retryAt = providerCooldowns.get(provider.id) || 0;
  return retryAt > Date.now();
}

function markProviderFailure(provider, error) {
  const message = String(error?.message || error || '');
  if (/rate limit|quota|insufficient balance|payment required|402|429/i.test(message)) {
    providerCooldowns.set(provider.id, Date.now() + PROVIDER_COOLDOWN_MS);
  }
}

function configuredModelChain() {
  const chain = MODEL_CHAIN.length > 0
    ? MODEL_CHAIN
    : [MODEL_PROVIDER_PRESETS.primary.id === 'local-ollama' ? 'ollama' : 'primary'];
  const providers = [];
  const seen = new Set();
  for (const key of chain) {
    const provider = MODEL_PROVIDER_PRESETS[key] || null;
    if (!provider || seen.has(provider.id)) {
      continue;
    }
    if (provider.type === 'openai-compatible' && !provider.apiKey) {
      continue;
    }
    seen.add(provider.id);
    providers.push(provider);
  }
  if (!seen.has('ollama')) {
    providers.push(MODEL_PROVIDER_PRESETS.ollama);
  }
  return providers;
}

async function callOllamaMessages(messages, provider = MODEL_PROVIDER_PRESETS.primary, options = {}) {
  const baseUrl = provider.baseUrl || AI_BASE_URL;
  const ollamaBaseUrl = baseUrl.endsWith('/v1')
    ? baseUrl.slice(0, -3)
    : baseUrl;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), provider.timeoutMs || MODEL_TIMEOUT_MS);
  const response = await fetch(`${ollamaBaseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    signal: controller.signal,
    body: JSON.stringify({
      model: provider.model || MODEL,
      messages,
      stream: false,
      keep_alive: OLLAMA_KEEP_ALIVE,
      options: {
        num_predict: options.maxTokens || MAX_TOKENS,
        temperature: options.temperature ?? TEMPERATURE,
        num_ctx: options.numCtx || 768,
        num_thread: Number(process.env.POKONTACT_OLLAMA_THREADS || 2),
      },
    }),
  }).finally(() => clearTimeout(timeout));
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Ollama returned ${response.status}.`);
  }
  const reply = cleanText(payload.message?.content, 5000);
  if (!reply) {
    throw new Error('Ollama returned an empty reply.');
  }
  return reply;
}

async function callOpenAiCompatibleMessages(messages, provider, options = {}) {
  const controller = new AbortController();
  const timeoutMs = provider.timeoutMs || MODEL_TIMEOUT_MS;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const baseUrl = (provider.baseUrl || AI_BASE_URL).replace(/\/+$/, '');
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${provider.apiKey}`,
      'Content-Type': 'application/json',
    },
    signal: controller.signal,
    body: JSON.stringify({
      model: provider.model || MODEL,
      messages,
      max_tokens: options.maxTokens || MAX_TOKENS,
      temperature: options.temperature ?? TEMPERATURE,
    }),
  }).finally(() => clearTimeout(timeout));
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error?.message || payload.message || `Model provider returned ${response.status}.`);
  }
  const reply = cleanText(payload.choices?.[0]?.message?.content, 5000);
  if (!reply) {
    throw new Error('Model provider returned an empty reply.');
  }
  return reply;
}

async function callPollinationsMessages(messages, provider) {
  const prompt = messages
    .map((entry) => `${entry.role.toUpperCase()}:\n${entry.content}`)
    .join('\n\n');
  const controller = new AbortController();
  const timeoutMs = provider.timeoutMs || MODEL_TIMEOUT_MS;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const url = new URL(`${(provider.baseUrl || 'https://text.pollinations.ai').replace(/\/+$/, '')}/${encodeURIComponent(prompt)}`);
  url.searchParams.set('model', provider.model || 'openai-fast');
  url.searchParams.set('private', 'true');
  const response = await fetch(url, {
    method: 'GET',
    headers: { Accept: 'text/plain' },
    signal: controller.signal,
  }).finally(() => clearTimeout(timeout));
  const text = cleanText(await response.text().catch(() => ''), 5000);
  if (!response.ok) {
    throw new Error(text || `Pollinations returned ${response.status}.`);
  }
  if (!text) {
    throw new Error('Pollinations returned an empty reply.');
  }
  return text;
}

async function callOllamaModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider = MODEL_PROVIDER_PRESETS.primary }) {
  const baseUrl = provider.baseUrl || AI_BASE_URL;
  const ollamaBaseUrl = baseUrl.endsWith('/v1')
    ? baseUrl.slice(0, -3)
    : baseUrl;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), provider.timeoutMs || MODEL_TIMEOUT_MS);
  const response = await fetch(`${ollamaBaseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    signal: controller.signal,
    body: JSON.stringify({
      model: provider.model || MODEL,
      messages: modelMessages({ message, chatRecord, user, page, pageContext, marketplaceContext }),
      stream: false,
      keep_alive: OLLAMA_KEEP_ALIVE,
      options: {
        num_predict: MAX_TOKENS,
        temperature: TEMPERATURE,
        num_ctx: 768,
        num_thread: Number(process.env.POKONTACT_OLLAMA_THREADS || 2),
      },
    }),
  }).finally(() => clearTimeout(timeout));
  try {
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload.error || `Ollama returned ${response.status}.`);
    }
    const reply = cleanText(payload.message?.content, 5000);
    if (!reply) {
      throw new Error('Ollama returned an empty reply.');
    }
    return reply;
  } catch (error) {
    if (error.name === 'AbortError') {
      throw new Error(`Ollama timed out after ${provider.timeoutMs || MODEL_TIMEOUT_MS}ms.`);
    }
    throw error;
  }
}

async function callOpenAiCompatibleModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider }) {
  const controller = new AbortController();
  const timeoutMs = provider.timeoutMs || MODEL_TIMEOUT_MS;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const baseUrl = (provider.baseUrl || AI_BASE_URL).replace(/\/+$/, '');
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${provider.apiKey}`,
      'Content-Type': 'application/json',
    },
    signal: controller.signal,
    body: JSON.stringify({
      model: provider.model || MODEL,
      messages: modelMessages({ message, chatRecord, user, page, pageContext, marketplaceContext }),
      max_tokens: MAX_TOKENS,
      temperature: TEMPERATURE,
    }),
  }).finally(() => clearTimeout(timeout));
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error?.message || payload.message || `Model provider returned ${response.status}.`);
  }
  const reply = cleanText(payload.choices?.[0]?.message?.content, 5000);
  if (!reply) {
    throw new Error('Model provider returned an empty reply.');
  }
  return reply;
}

async function callPollinationsTextModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider }) {
  const prompt = modelMessages({ message, chatRecord, user, page, pageContext, marketplaceContext })
    .map((entry) => `${entry.role.toUpperCase()}:\n${entry.content}`)
    .join('\n\n');
  const controller = new AbortController();
  const timeoutMs = provider.timeoutMs || MODEL_TIMEOUT_MS;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const url = new URL(`${(provider.baseUrl || 'https://text.pollinations.ai').replace(/\/+$/, '')}/${encodeURIComponent(prompt)}`);
  url.searchParams.set('model', provider.model || 'openai-fast');
  url.searchParams.set('private', 'true');
  url.searchParams.set('system', systemPrompt(user));
  const response = await fetch(url, { signal: controller.signal }).finally(() => clearTimeout(timeout));
  const text = await response.text();
  if (!response.ok) {
    throw new Error(text || `Pollinations returned ${response.status}.`);
  }
  const reply = cleanText(text, 5000);
  if (!reply) {
    throw new Error('Pollinations returned an empty reply.');
  }
  return reply;
}

async function callProviderModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider }) {
  if (provider.type === 'ollama') {
    return callOllamaModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider });
  }
  if (provider.type === 'pollinations-text') {
    return callPollinationsTextModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider });
  }
  return callOpenAiCompatibleModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider });
}

async function callLanguageModel({ message, chatRecord, user, page, pageContext, marketplaceContext }) {
  const providers = configuredModelChain();
  for (const provider of providers) {
    if (isProviderCoolingDown(provider)) {
      continue;
    }
    try {
      const reply = await callProviderModel({ message, chatRecord, user, page, pageContext, marketplaceContext, provider });
      if (reply) {
        return { reply, provider: provider.id, model: provider.model };
      }
    } catch (error) {
      markProviderFailure(provider, error);
      console.error(`pokontact provider ${provider.id} fallback`, error.message || error);
    }
  }
  return null;
}

async function warmModel() {
  if (!isOllamaProvider()) {
    return;
  }
  try {
    await callOllamaModel({
      message: 'hi',
      chatRecord: [],
      user: { username: 'warmup' },
    });
  } catch (error) {
    console.error('pokontact warmup failed', error.message || error);
  }
}

async function generateFallbackReply({ message, user }) {
  const intent = classifyIntent(message);
  let reply;
  let actions = [];
  if (intent === 'unsafe-cyber') {
    reply = unsafeCyberReply(message);
  } else if (intent === 'navigation') {
    reply = navigationReply(message);
  } else if (isTechnicalIntent(intent)) {
    reply = docsReply(message, intent);
  } else if (intent === 'status') {
    reply = await statusReply(message);
  } else if (intent === 'greeting') {
    reply = greetingReply(message);
  } else if (intent === 'clarify') {
    reply = clarifyReply(message);
  } else if (intent === 'inquiry') {
    reply = inquiryReply();
  } else if (intent === 'card') {
    const suggestion = cardSuggestion();
    reply = suggestion.reply;
    actions = suggestion.actions;
  } else if (intent === 'nft') {
    reply = nftReply();
  } else if (intent === 'network') {
    reply = networkReply();
  } else if (intent === 'external-chain') {
    reply = externalChainReply(message);
  } else if (intent === 'node') {
    reply = nodeReply(message);
  } else if (intent === 'buy') {
    reply = buyReply(message);
  } else if (intent === 'funny') {
    reply = funnyReply(message);
  } else if (intent === 'introduction') {
    reply = introductionReply(message);
  } else if (intent === 'favorite-pokemon') {
    reply = favoritePokemonReply(message);
  } else if (intent === 'card-history') {
    reply = pokemonCardHistoryReply(message);
  } else if (intent === 'wellbeing') {
    reply = wellbeingReply(message);
  } else if (intent === 'unknown') {
    reply = unknownReply(message);
  } else if (intent === 'earn') {
    reply = earnReply(message);
  } else if (intent === 'marketplace') {
    reply = marketplaceReply(message);
  } else if (intent === 'crypto') {
    reply = cryptoReply();
  } else if (intent === 'project') {
    reply = projectReply(user, message);
  } else {
    reply = unknownReply(message);
  }
  return { reply, intent, ai: false, actions };
}

async function generateReply({ message, chatRecord, user, page, pageContext, marketplaceContext }) {
  const text = normalizeIntentText(message);
  const context = conversationContext(chatRecord);
  const publicFact = await trivialInternetLookup(message);
  if (publicFact) {
    return publicFact;
  }
  if ((context.cardHistory || context.baseSet) && looksLikeShortCardHistoryFollowUp(text)) {
    return {
      reply: pokemonCardHistoryReply(message),
      intent: 'card-history',
      ai: true,
      source: 'context-follow-up',
    };
  }
  const intent = classifyIntent(message);
  if (shouldUseImmediateCuratedReply(intent, message)) {
    const fallback = await generateFallbackReply({ message, user });
    return { ...fallback, ai: true, source: 'curated-local' };
  }
  if (canEscalateUnknown(intent) && wasLastAssistantUnsure(chatRecord)) {
    try {
      const modelReply = await callEscalatedModel({ message, chatRecord, user, page, pageContext, marketplaceContext });
      if (modelReply) {
        return { reply: modelReply, intent, ai: true, source: 'model-escalated' };
      }
    } catch (error) {
      console.error('pokontact escalated model fallback', error.message || error);
    }
    return {
      reply: escalatedUnknownReply(message),
      intent,
      ai: true,
      source: 'curated-escalation-fallback',
    };
  }
  try {
    const modelResult = await callLanguageModel({ message, chatRecord, user, page, pageContext, marketplaceContext });
    if (modelResult?.reply) {
      return {
        reply: modelResult.reply,
        intent,
        ai: true,
        provider: modelResult.provider,
        model: modelResult.model,
      };
    }
  } catch (error) {
    console.error('pokontact model fallback', error.message || error);
  }
  return generateFallbackReply({ message, user });
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 128 * 1024) {
        reject(Object.assign(new Error('Request body is too large.'), { statusCode: 413 }));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(Object.assign(new Error('Invalid JSON body.'), { statusCode: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function isAuthorized(req) {
  if (!SERVICE_TOKEN) {
    return process.env.NODE_ENV !== 'production';
  }
  return req.headers.authorization === `Bearer ${SERVICE_TOKEN}`;
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', `http://${req.headers.host || `${HOST}:${PORT}`}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      sendJson(res, 200, {
        ok: true,
        assistant: 'Pokontact',
        provider: MODEL_PROVIDER,
        model: MODEL,
        ai: Boolean(AI_API_KEY),
      });
      return;
    }

    if (req.method !== 'POST' || (url.pathname !== '/chat' && url.pathname !== '/social-post')) {
      sendJson(res, 404, { error: 'Not found.' });
      return;
    }

    if (!isAuthorized(req)) {
      sendJson(res, 401, { error: 'Unauthorized.' });
      return;
    }

    const body = await readJsonBody(req);
    if (url.pathname === '/social-post') {
      const result = await callSocialPostModel(body);
      sendJson(res, 200, {
        ok: true,
        ...result,
        assistant: 'PokoinSocialAgent',
      });
      return;
    }

    const message = cleanText(body?.message, 3000);
    const chatRecord = cleanChatRecord(body?.messages);
    const page = cleanText(body?.page, 500);
    const structuredPageContext = cleanPageContext(body?.pageContext);
    const marketplaceContext = cleanMarketplaceContext(body?.marketplaceContext);
    const user = {
      uid: cleanText(body?.user?.uid, 120),
      username: cleanText(body?.user?.username, 80) || 'guest',
      email: cleanText(body?.user?.email, 160),
    };

    if (message.length < 2) {
      sendJson(res, 400, { error: 'Write a message for Pokontact.' });
      return;
    }

    const result = await generateReply({
      message,
      chatRecord,
      user,
      page,
      pageContext: structuredPageContext,
      marketplaceContext,
    });
    result.reply = sanitizePokoEmoji(result.reply);
    sendJson(res, 200, {
      ...result,
      assistant: 'Pokontact',
      provider: result.provider || MODEL_PROVIDER,
      model: result.model || MODEL,
      ai: Boolean(result.ai),
      source: result.source || 'peer2-service',
    });
  } catch (error) {
    sendJson(res, error.statusCode || 500, {
      error: error.message || 'Pokontact service failed.',
      assistant: 'Pokontact',
    });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Pokontact service listening on http://${HOST}:${PORT}`);
  warmModel();
  if (WARM_INTERVAL_MS > 0) {
    setInterval(warmModel, WARM_INTERVAL_MS).unref();
  }
});
