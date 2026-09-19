'use strict';

const net = require('net');

const HOST = process.env.VALKEY_HOST || '127.0.0.1';
const PORT = Number(process.env.VALKEY_PORT || 6379);
const TIMEOUT_MS = Number(process.env.VALKEY_TIMEOUT_MS || 400);

function encode(parts) {
  let out = `*${parts.length}\r\n`;
  for (const part of parts) {
    const text = String(part);
    out += `$${Buffer.byteLength(text)}\r\n${text}\r\n`;
  }
  return out;
}

function parseReply(buf) {
  const firstNl = buf.indexOf('\r\n');
  if (firstNl < 0) {
    return null;
  }
  const head = buf.slice(0, firstNl).toString('utf8');
  const kind = head[0];
  if (kind === '+' || kind === '-') {
    return { value: kind === '+' ? head.slice(1) : null, used: firstNl + 2 };
  }
  if (kind === ':') {
    return { value: Number(head.slice(1)), used: firstNl + 2 };
  }
  if (kind === '$') {
    const size = Number(head.slice(1));
    if (size < 0) {
      return { value: null, used: firstNl + 2 };
    }
    const start = firstNl + 2;
    const end = start + size + 2;
    if (buf.length < end) {
      return null;
    }
    return { value: buf.slice(start, start + size).toString('utf8'), used: end };
  }
  return { value: null, used: buf.length };
}

function command(parts) {
  return new Promise((resolve) => {
    const sock = net.connect({ host: HOST, port: PORT });
    const chunks = [];
    const timer = setTimeout(() => {
      sock.destroy();
      resolve(null);
    }, TIMEOUT_MS);
    function finish(value) {
      clearTimeout(timer);
      sock.end();
      resolve(value);
    }
    sock.on('error', () => finish(null));
    sock.on('data', (chunk) => {
      chunks.push(chunk);
      const parsed = parseReply(Buffer.concat(chunks));
      if (parsed) {
        finish(parsed.value);
      }
    });
    sock.on('connect', () => {
      sock.write(encode(parts));
    });
  });
}

async function getJson(key) {
  const raw = await command(['GET', key]);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

async function setJson(key, value, ttlSeconds) {
  if (value == null || !ttlSeconds) {
    return false;
  }
  const reply = await command(['SETEX', key, String(ttlSeconds), JSON.stringify(value)]);
  return reply === 'OK';
}

module.exports = { getJson, setJson, command };
