'use strict';

// Sends 6 made-up weeks through writeWeekly's prompt and check with an API
// key, and prints each week's time, paragraph and whether the check passed.
// Run: ANTHROPIC_API_KEY=... node functions/tools/weekly-words-trial.js

const Anthropic = require('@anthropic-ai/sdk');
const { checkParagraph, messageRequest, parseMessage, validFigures } = require('../weekly_words.js');

function habit(i, unitOne, unitOther, total, entries, days, usual) {
  return { habit: `Habit ${String.fromCharCode(65 + i)}`, unitOne, unitOther, total, entries, days, usual };
}

const weeks = [
  {
    entries: '20',
    habits: [habit(0, 'glass', 'glasses', '9', '6', '5', '7'), habit(1, 'cup', 'cups', '14', '14', '7', '14')],
    hours: [{ from: '20:00', to: '21:00', entries: '6' }, { from: '08:00', to: '09:00', entries: '5' }],
    tags: [{ path: 'work/long-day', entries: '4' }, { path: 'social/friends', entries: '2' }],
    ownWords: '1',
  },
  {
    entries: '3',
    habits: [habit(0, 'cigarette', 'cigarettes', '3', '3', '2', '11.3')],
    hours: [{ from: '22:00', to: '23:00', entries: '2' }],
    tags: [],
    ownWords: '0',
  },
  {
    entries: '41',
    habits: [
      habit(0, 'drink', 'drinks', '12.5', '10', '4', '8.8'),
      habit(1, 'puff', 'puffs', '25', '25', '6', null),
      habit(2, 'hour', 'hours', '6', '6', '6', '5.5'),
    ],
    hours: [
      { from: '23:00', to: '00:00', entries: '9' },
      { from: '21:00', to: '22:00', entries: '7' },
      { from: '13:00', to: '14:00', entries: '7' },
    ],
    tags: [{ path: 'social/offered', entries: '5' }, { path: 'social', entries: '3' }],
    ownWords: '6',
  },
  {
    entries: '0',
    habits: [habit(0, 'glass', 'glasses', '0', '0', '0', '4'), habit(1, 'joint', 'joints', '0', '0', '0', null)],
    hours: [],
    tags: [],
    ownWords: '0',
  },
  {
    entries: '7',
    habits: [habit(0, 'can of 330ml', 'cans of 330ml', '7', '7', '3', '7')],
    hours: [{ from: '18:00', to: '19:00', entries: '4' }],
    tags: [{ path: 'work', entries: '7' }],
    ownWords: '2',
  },
  {
    entries: '16',
    habits: [habit(0, 'minute', 'minutes', '240', '8', '5', '195'), habit(1, 'bet', 'bets', '8', '8', '2', '1.3')],
    hours: [{ from: '00:00', to: '01:00', entries: '6' }],
    tags: [{ path: 'social/alone', entries: '6' }],
    ownWords: '0',
  },
];

async function main() {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('Set ANTHROPIC_API_KEY.');
    process.exit(1);
  }
  const client = new Anthropic({ timeout: 15000, maxRetries: 0 });
  for (const [i, week] of weeks.entries()) {
    const figures = validFigures(week);
    if (figures === null) {
      console.log(`week ${i + 1}: figures refused`);
      continue;
    }
    const start = process.hrtime.bigint();
    let parsed;
    try {
      parsed = parseMessage(await client.messages.create(messageRequest(figures)));
    } catch (e) {
      parsed = { text: null, reason: `api_error ${e.status || ''}` };
    }
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    const check = parsed.text === null ? parsed.reason : checkParagraph(parsed.text, figures);
    console.log(`week ${i + 1}: ${seconds.toFixed(2)} s, check ${check === 'ok' ? 'passed' : `failed (${check})`}`);
    console.log(`  ${parsed.text}`);
  }
}

main();
