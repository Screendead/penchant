'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  MODEL,
  checkParagraph,
  messageRequest,
  parseMessage,
  validFigures,
  writeWeekly,
} = require('./weekly_words.js');

// The same week as test/weekly_words_test.dart's.
function request() {
  return {
    entries: '20',
    habits: [
      { habit: 'Habit A', unitOne: 'glass', unitOther: 'glasses', total: '9', entries: '6', days: '5', usual: '7' },
      { habit: 'Habit B', unitOne: 'cup', unitOther: 'cups', total: '14', entries: '14', days: '7', usual: '10.5' },
      { habit: 'Habit C', unitOne: 'minute', unitOther: 'minutes', total: '0', entries: '0', days: '0', usual: null },
    ],
    hours: [{ from: '20:00', to: '21:00', entries: '6' }],
    tags: [
      { path: 'social/offered', label: 'ignored', entries: '4' },
      { path: 'social', entries: '2' },
    ],
    ownWords: '3',
  };
}

// The cases test/weekly_words_test.dart checks too.
const CASES = [
  ['Habit A came to 9 glasses over 5 days. Habit B was 14 cups, usually 10.5. Most were from 20:00 to 21:00.', 'ok'],
  ['You tagged "Who was there › Offered one" 4 times, and 3 tags were in your own words.', 'ok'],
  ['Habit A came to 9 glasses, 8 more than usual.', 'number'],
  ['Habit A came to nine glasses.', 'number_word'],
  ['Habit A came to 9 glasses, twice your usual.', 'number_word'],
  ['Habit D came to 9 glasses.', 'placeholder'],
  ['Habit A came to 9 glasses after 8pm.', 'number'],
  ['Habit A came to 9½ glasses.', 'number'],
  ['  ', 'empty'],
];

test('the request names the model, turns thinking off the way Sonnet 5.5 accepts and sends the figures alone', () => {
  const figures = validFigures(request());
  const body = messageRequest(figures);
  assert.equal(body.model, 'claude-sonnet-5-5');
  assert.equal(MODEL, 'claude-sonnet-5-5');
  assert.deepEqual(body.thinking, { type: 'between_tools' });
  assert.deepEqual(body.output_config, { effort: 'low' });
  assert.equal(body.temperature, undefined);
  assert.equal(body.messages.length, 1);
  assert.deepEqual(JSON.parse(body.messages[0].content), figures);
  assert.match(body.system, /3 to 5/);
  assert.match(body.system, /second person/);
  assert.match(body.system, /no advice/);
  assert.match(body.system, /other people/);
});

test('validFigures copies only known fields and takes tag labels from the tree', () => {
  const data = request();
  data.uid = 'someone';
  data.habits[0].name = 'Wine';
  const figures = validFigures(data);
  assert.equal(figures.uid, undefined);
  assert.equal(figures.habits[0].name, undefined);
  assert.deepEqual(figures.tags, [
    { path: 'social/offered', label: 'Who was there › Offered one', entries: '4' },
    { path: 'social', label: 'Who was there', entries: '2' },
  ]);
  assert.equal(figures.habits[2].usual, null);
});

test('validFigures refuses what is out of bounds', () => {
  const bad = [
    (d) => { d.habits = []; },
    (d) => { d.habits[1].habit = 'Habit C'; },
    (d) => { d.habits[0].habit = 'Wine'; },
    (d) => { d.habits[0].total = 9; },
    (d) => { d.habits[0].total = '-9'; },
    (d) => { d.habits[0].unitOther = 'x'.repeat(21); },
    (d) => { d.habits[0].usual = 'usual'; },
    (d) => { delete d.habits[0].days; },
    (d) => { d.hours[0].from = '8pm'; },
    (d) => { d.hours = [d.hours[0], d.hours[0], d.hours[0], d.hours[0]]; },
    (d) => { d.tags[0].path = 'my own words'; },
    (d) => { d.tags[1].path = 'social/offered'; },
    (d) => { d.ownWords = 'three'; },
    (d) => { delete d.entries; },
  ];
  for (const change of bad) {
    const d = request();
    change(d);
    assert.equal(validFigures(d), null, change.toString());
  }
  assert.equal(validFigures(null), null);
  assert.equal(validFigures('figures'), null);
});

test('checkParagraph lets through only sent numbers and placeholders, and no number words', () => {
  const figures = validFigures(request());
  for (const [text, reason] of CASES) {
    assert.equal(checkParagraph(text, figures), reason, text);
  }
});

test('parseMessage reads text blocks by type and names refusals and cut-offs', () => {
  assert.deepEqual(
    parseMessage({ stop_reason: 'end_turn', content: [{ type: 'thinking', thinking: '' }, { type: 'text', text: ' Hi. ' }] }),
    { text: 'Hi.', reason: 'ok' },
  );
  assert.deepEqual(parseMessage({ stop_reason: 'refusal', content: [] }), { text: null, reason: 'refusal' });
  assert.deepEqual(parseMessage({ stop_reason: 'max_tokens', content: [{ type: 'text', text: 'Habit' }] }), {
    text: null,
    reason: 'max_tokens',
  });
  assert.deepEqual(parseMessage({ stop_reason: 'end_turn', content: [] }), { text: null, reason: 'empty' });
  assert.deepEqual(parseMessage(null), { text: null, reason: 'refusal' });
  assert.deepEqual(parseMessage({ stop_reason: 'end_turn', content: 'text' }), { text: null, reason: 'empty' });
});

test('writeWeekly answers a checked paragraph, and drops one that fails', async () => {
  const figures = validFigures(request());
  const reply = (text) => ({
    messages: { create: async () => ({ stop_reason: 'end_turn', content: [{ type: 'text', text }] }) },
  });
  assert.deepEqual(await writeWeekly(reply(CASES[0][0]), figures), { text: CASES[0][0], reason: 'ok' });
  assert.deepEqual(await writeWeekly(reply(CASES[2][0]), figures), { text: null, reason: 'number' });
  const failing = { messages: { create: async () => { throw new Error('down'); } } };
  assert.deepEqual(await writeWeekly(failing, figures), { text: null, reason: 'api_error' });
});
