const fs = require('fs');
const path = require('path');

const filePath = process.argv[2] ||
  path.join(__dirname, '..', 'training', 'pokontact-behavior-seed.jsonl');

const lines = fs.readFileSync(filePath, 'utf8')
  .split(/\r?\n/)
  .filter((line) => line.trim());

let failed = 0;
lines.forEach((line, index) => {
  try {
    const example = JSON.parse(line);
    if (!Array.isArray(example.messages) || example.messages.length < 2) {
      throw new Error('missing messages array');
    }
    if (!example.messages.some((message) => message.role === 'assistant')) {
      throw new Error('missing assistant message');
    }
    for (const message of example.messages) {
      if (!['system', 'user', 'assistant'].includes(message.role)) {
        throw new Error(`invalid role ${message.role}`);
      }
      if (typeof message.content !== 'string' || message.content.trim().length === 0) {
        throw new Error('empty message content');
      }
    }
  } catch (error) {
    failed += 1;
    console.error(`Invalid JSONL line ${index + 1}: ${error.message}`);
  }
});

if (failed > 0) {
  process.exit(1);
}

console.log(`Validated ${lines.length} training example(s).`);
