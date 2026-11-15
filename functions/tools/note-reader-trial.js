'use strict';

// Sends the made-up notes of tools/note-tagging-trial.swift through readNote's
// prompt and checks with an API key, and prints each note's time and tags.
// Run: ANTHROPIC_API_KEY=... node functions/tools/note-reader-trial.js

const Anthropic = require('@anthropic-ai/sdk');
const { messageRequest, parseMessage } = require('../note_reader.js');

const notes = [
  'Rough one. Got out of the quarterly review at six, boss tore into the roadmap, went straight to the pub with Sam and stayed till close.',
  'Had a cigarette on the balcony after dinner, nothing going on really, just what I do.',
  "Couldn't sleep, back was killing me, smoked a joint to take the edge off.",
  "Sarah's wedding. Open bar, everyone was at it, lost count after the speeches.",
  'Third coffee before ten because the baby was up all night.',
  'Scrolling in bed, saw an ad for that gin, ordered a bottle and opened the old one.',
  'Flight delayed four hours, sat in the airport bar on my own.',
  'Deadline Friday. Vaped at my desk all afternoon without noticing.',
  "Nothing unusual. Sunday roast at mum's, a couple of glasses of red.",
  'Argument with Alex about money, then drank most of a bottle of wine on the sofa.',
  "Did a line at Tom's birthday because it was going round, regret it.",
  'Ran 10k this morning, beer in the garden after, felt earned.',
];

async function main() {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('Set ANTHROPIC_API_KEY.');
    process.exit(1);
  }
  const client = new Anthropic({ timeout: 8000, maxRetries: 0 });
  const times = [];
  for (const note of notes) {
    const start = process.hrtime.bigint();
    let result;
    let candidates = [];
    try {
      const message = await client.messages.create(messageRequest(note));
      result = parseMessage(message, note);
      try {
        const text = message.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
        candidates = JSON.parse(text).tags || [];
      } catch {
        candidates = [];
      }
    } catch (error) {
      result = { tags: [], dropped: 0, reason: `api_error ${error.status ?? ''} ${error.message}` };
    }
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    times.push(seconds);
    const kept = new Set(result.tags.map((t) => `${t.path}|${t.quote}`));
    const dropped = candidates.filter((t) => !kept.has(`${t.path}|${t.quote}`));
    console.log(`${seconds.toFixed(1)}s  ${result.reason}`);
    console.log(`    ${note}`);
    for (const t of result.tags) console.log(`    + ${t.path}  "${t.quote}"`);
    for (const t of dropped) console.log(`    - dropped ${t.path}  "${t.quote}"`);
  }
  const sorted = [...times].sort((a, b) => a - b);
  console.log(
    `median ${sorted[Math.floor(sorted.length / 2)].toFixed(1)}s  max ${sorted[sorted.length - 1].toFixed(1)}s`,
  );
}

main();
