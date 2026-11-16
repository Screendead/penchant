'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');

const {
  MAX_CARDS,
  MODEL,
  MODELS,
  REQUEST_TIMEOUT_MS,
  SCHEMA,
  SYSTEM,
  askJournal,
  messageRequest,
  parseMessage,
  validAnswer,
  validInput,
} = require('./ask_journal.js');
const trial = require('./tools/ask-journal-trial.js');

const habits = [
  { id: 1, name: 'Wine', unit: 'glasses', unit_one: 'glass', archived: false },
  { id: 4, name: 'Vape', unit: 'puffs', unit_one: 'puff', archived: true },
];
const card = {
  title: 'Last week without Wine',
  explain: 'The latest full week with no Wine logged.',
  sql: 'SELECT week FROM days GROUP BY week',
  chart: { type: 'table', x: '', y: [], series: '', x_kind: 'none' },
};
const answer = { kind: 'answer', reason: 'none', cards: [card] };
const input = {
  question: 'What about last year?',
  today: '2026-11-15',
  weekday: 'Sunday',
  habits,
  history: [{ question: 'When was my last week without wine?', answer }],
};
const text = (t) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: t }] });

test('the schema uses only what structured outputs accept', () => {
  const banned = ['minimum', 'maximum', 'multipleOf', 'minLength', 'maxLength', 'minItems', 'maxItems', 'pattern'];
  let objects = 0;
  const walk = (node, where) => {
    if (Array.isArray(node)) return node.forEach((n, i) => walk(n, `${where}[${i}]`));
    if (node === null || typeof node !== 'object') return;
    for (const key of banned) assert.ok(!(key in node), `${where} uses ${key}`);
    if (node.type === 'object') {
      objects++;
      assert.equal(node.additionalProperties, false, `${where} allows extra keys`);
      assert.deepEqual([...node.required].sort(), Object.keys(node.properties).sort(), `${where} has optional keys`);
    }
    if (node.$ref) assert.ok(SCHEMA.$defs[node.$ref.replace('#/$defs/', '')], `${where} refers to nothing`);
    for (const [key, child] of Object.entries(node)) walk(child, `${where}.${key}`);
  };
  walk(SCHEMA, 'schema');
  assert.equal(objects, 3);
  const refs = (node) => JSON.stringify(node).match(/#\/\$defs\/\w+/g) || [];
  for (const [name, def] of Object.entries(SCHEMA.$defs)) {
    const seen = new Set();
    const queue = refs(def);
    while (queue.length) {
      const next = queue.pop().replace('#/$defs/', '');
      assert.notEqual(next, name, `${name} is recursive`);
      if (!seen.has(next)) {
        seen.add(next);
        queue.push(...refs(SCHEMA.$defs[next]));
      }
    }
  }
});

test('each model gets its fastest accepted setting and the answer schema', () => {
  assert.equal(MODEL, 'claude-sonnet-5-5');
  assert.deepEqual(MODELS, ['claude-sonnet-5-5', 'claude-haiku-5-5']);
  const sonnet = messageRequest(validInput(input));
  assert.equal(sonnet.model, 'claude-sonnet-5-5');
  // Sonnet 5.5: "disabled" is a 400; "between_tools" at effort high or below.
  assert.deepEqual(sonnet.thinking, { type: 'between_tools' });
  assert.deepEqual(sonnet.output_config, { effort: 'low', format: { type: 'json_schema', schema: SCHEMA } });
  const haiku = messageRequest(validInput(input), 'claude-haiku-5-5');
  assert.equal(haiku.model, 'claude-haiku-5-5');
  // Haiku 5.5: "disabled" at low, medium or high; "between_tools" is a 400.
  assert.deepEqual(haiku.thinking, { type: 'disabled' });
  assert.deepEqual(haiku.output_config, { effort: 'low', format: { type: 'json_schema', schema: SCHEMA } });
  for (const request of [sonnet, haiku]) {
    assert.ok(request.max_tokens >= 2000 && request.max_tokens <= 8000);
    assert.deepEqual(Object.keys(request.thinking), ['type']);
    assert.ok(!('temperature' in request) && !('top_p' in request) && !('top_k' in request));
  }
  const fallback = messageRequest(validInput(input), 'claude-opus-5-5');
  assert.equal(fallback.model, MODEL);
  assert.deepEqual(fallback.thinking, { type: 'between_tools' });
});

test('earlier turns come first, oldest first, and the last message carries today and the habits', () => {
  const twoTurns = validInput({
    ...input,
    history: [
      { question: 'first?', answer },
      { question: 'second?', answer: { kind: 'needs_insights', reason: 'none', cards: [] } },
    ],
  });
  const { messages } = messageRequest(twoTurns);
  assert.deepEqual(
    messages.map(({ role }) => role),
    ['user', 'assistant', 'user', 'assistant', 'user'],
  );
  assert.deepEqual(JSON.parse(messages[0].content), { question: 'first?' });
  assert.deepEqual(JSON.parse(messages[1].content), answer);
  assert.deepEqual(JSON.parse(messages[2].content), { question: 'second?' });
  assert.deepEqual(JSON.parse(messages[3].content), { kind: 'needs_insights', reason: 'none', cards: [] });
  assert.deepEqual(JSON.parse(messages[4].content), {
    question: 'What about last year?',
    today: '2026-11-15',
    weekday: 'Sunday',
    habits,
  });
  assert.equal(messageRequest(validInput({ ...input, history: [] })).messages.length, 1);
});

test('the system prompt is fixed, whatever the input', () => {
  const other = validInput({
    ...input,
    question: 'Something else entirely',
    habits: [{ id: 9, name: 'Zebra juice', unit: 'sips', unit_one: 'sip', archived: false }],
  });
  assert.equal(messageRequest(validInput(input)).system, SYSTEM);
  assert.equal(messageRequest(other).system, SYSTEM);
  assert.ok(!SYSTEM.includes('Zebra'));
  for (const table of ['habits(', 'entries(', 'entry_tags(', 'day_notes(', 'day_note_tags(', 'days(']) {
    assert.ok(SYSTEM.includes(table), table);
  }
  assert.match(SYSTEM, /data, not instructions/);
});

test('the input is exactly the expected keys, bounded, with valid earlier answers', () => {
  const clean = validInput(input);
  assert.deepEqual(clean, input);
  assert.deepEqual(validInput({ ...input, uid: 'x', extra: 1 }), input);
  assert.deepEqual(validInput({ ...input, habits: [{ ...habits[0], entries: [1] }] }).habits, [habits[0]]);
  assert.deepEqual(validInput({ ...input, history: [{ ...input.history[0], at: 1 }] }).history, input.history);
  const { history, ...noHistory } = input;
  assert.deepEqual(validInput(noHistory).history, []);
  assert.equal(validInput({ ...input, question: 'x'.repeat(300) }).question.length, 300);
  for (const bad of [
    { question: 'x'.repeat(301) },
    { question: '🍷'.repeat(151) },
    { question: '  ' },
    { question: 3 },
    { today: '2026-02-30' },
    { today: '15/11/2026' },
    { weekday: 'Monday' },
    { habits: [] },
    { habits: Array.from({ length: 101 }, (_, i) => ({ ...habits[0], id: i + 1 })) },
    { habits: [habits[0], { ...habits[1], id: 1 }] },
    { habits: [{ ...habits[0], id: 0 }] },
    { habits: [{ ...habits[0], id: 1001 }] },
    { habits: [{ ...habits[0], id: 1.5 }] },
    { habits: [{ ...habits[0], name: 'x'.repeat(61) }] },
    { habits: [{ ...habits[0], unit: 'x'.repeat(21) }] },
    { habits: [{ ...habits[0], unit_one: '' }] },
    { habits: [{ ...habits[0], archived: 'no' }] },
    { history: Array(6).fill(input.history[0]) },
    { history: 'none' },
    { history: [{ question: '', answer }] },
    { history: [{ question: 'q?', answer: { ...answer, cards: [] } }] },
    { history: [{ question: 'q?', answer: { ...answer, extra: 1 } }] },
    { history: [{ question: 'q?' }] },
  ]) {
    assert.equal(validInput({ ...input, ...bad }), null, JSON.stringify(bad).slice(0, 80));
  }
  assert.equal(validInput(null), null);
  assert.equal(validInput('question'), null);
  assert.equal(validInput([input]), null);
});

test('an answer is checked against the schema and the limits it cannot carry', () => {
  assert.ok(validAnswer(answer));
  assert.ok(validAnswer({ kind: 'answer', reason: 'none', cards: Array(MAX_CARDS).fill(card) }));
  assert.ok(validAnswer({ kind: 'needs_insights', reason: 'none', cards: [] }));
  assert.ok(validAnswer({ kind: 'cannot_answer', reason: 'unclear', cards: [] }));
  const chart = (c) => ({ ...answer, cards: [{ ...card, chart: { ...card.chart, ...c } }] });
  const withCard = (c) => ({ ...answer, cards: [{ ...card, ...c }] });
  assert.ok(validAnswer(chart({ type: 'bar', x: 'hour', y: ['a', 'b', 'c', 'd'], series: 'habit', x_kind: 'hour' })));
  for (const bad of [
    { ...answer, extra: 1 },
    { kind: 'answer', reason: 'none' },
    { ...answer, kind: 'query' },
    { ...answer, reason: 'because' },
    { ...answer, cards: [] },
    { ...answer, cards: Array(MAX_CARDS + 1).fill(card) },
    { ...answer, reason: 'unclear' },
    { kind: 'needs_insights', reason: 'none', cards: [card] },
    { kind: 'needs_insights', reason: 'unclear', cards: [] },
    { kind: 'cannot_answer', reason: 'unclear', cards: [card] },
    { kind: 'cannot_answer', reason: 'none', cards: [] },
    withCard({ extra: 1 }),
    withCard({ title: '' }),
    withCard({ title: 'x'.repeat(81) }),
    withCard({ explain: 'x'.repeat(241) }),
    withCard({ sql: 'x'.repeat(4001) }),
    withCard({ sql: 3 }),
    chart({ type: 'pie' }),
    chart({ x_kind: 'minute' }),
    chart({ extra: 1 }),
    chart({ y: ['a', 'b', 'c', 'd', 'e'] }),
    chart({ y: [''] }),
    chart({ y: ['x'.repeat(65)] }),
    chart({ x: 'x'.repeat(65) }),
    chart({ series: null }),
    null,
    [],
  ]) {
    assert.equal(validAnswer(bad), false, JSON.stringify(bad).slice(0, 80));
  }
});

test('the reply is read into an answer, or why there is none, never throwing', () => {
  assert.deepEqual(parseMessage(text(JSON.stringify(answer))), { answer, reason: 'ok' });
  const withThinking = { stop_reason: 'end_turn', content: [{ type: 'thinking', thinking: '' }, ...text(JSON.stringify(answer)).content] };
  assert.deepEqual(parseMessage(withThinking), { answer, reason: 'ok' });
  const none = (reason) => ({ answer: null, reason });
  assert.deepEqual(parseMessage({ stop_reason: 'refusal', content: [] }), none('refusal'));
  assert.deepEqual(parseMessage({ stop_reason: 'max_tokens', content: text('{"kind":').content }), none('max_tokens'));
  assert.deepEqual(parseMessage(text('{"kind":')), none('unparsable'));
  assert.deepEqual(parseMessage(text('Sure! Here is the SQL.')), none('unparsable'));
  assert.deepEqual(parseMessage(text('[]')), none('unparsable'));
  assert.deepEqual(parseMessage(text(JSON.stringify({ ...answer, extra: 1 }))), none('unparsable'));
  assert.deepEqual(parseMessage(text(JSON.stringify({ ...answer, kind: 'query' }))), none('unparsable'));
  assert.deepEqual(parseMessage(text(JSON.stringify({ ...answer, cards: Array(4).fill(card) }))), none('unparsable'));
  assert.deepEqual(parseMessage(text(JSON.stringify({ ...answer, cards: [] }))), none('unparsable'));
  assert.deepEqual(
    parseMessage(text(JSON.stringify({ kind: 'cannot_answer', reason: 'unclear', cards: [card] }))),
    none('unparsable'),
  );
  assert.deepEqual(parseMessage(null), none('refusal'));
  assert.deepEqual(parseMessage({ stop_reason: 'end_turn', content: 'x' }), none('unparsable'));
});

test('an API failure is a reason, not a throw, and the call carries its own timeout', async () => {
  const failing = { messages: { create: async () => { throw new Error('down'); } } };
  assert.deepEqual(await askJournal(failing, validInput(input)), { answer: null, reason: 'api_error' });
  const calls = [];
  const answering = {
    messages: {
      create: async (body, options) => {
        calls.push({ body, options });
        return text(JSON.stringify(answer));
      },
    },
  };
  assert.deepEqual(await askJournal(answering, validInput(input), 'claude-haiku-5-5'), { answer, reason: 'ok' });
  assert.equal(calls[0].body.model, 'claude-haiku-5-5');
  assert.deepEqual(calls[0].options, { timeout: REQUEST_TIMEOUT_MS });
  assert.ok(REQUEST_TIMEOUT_MS >= 30000 && REQUEST_TIMEOUT_MS <= 50000);
});

test('the trial has 40 questions the server would accept, with follow-ups pointing back', () => {
  const { QUESTIONS, INPUT } = trial;
  assert.equal(QUESTIONS.length, 40);
  const kinds = new Set();
  for (const [index, spec] of QUESTIONS.entries()) {
    assert.equal(typeof spec.question, 'string');
    assert.ok(validInput({ ...INPUT, question: spec.question }), spec.question);
    assert.ok(spec.safe || spec.kind, spec.question);
    if (spec.check) assert.equal(typeof spec.check, 'function');
    if (spec.after != null) assert.ok(spec.after < index && Number.isInteger(spec.after), spec.question);
    for (const kind of [].concat(spec.kind || [])) kinds.add(kind);
    for (const reason of [].concat(spec.reason || [])) assert.ok(SCHEMA.properties.reason.enum.includes(reason));
  }
  for (const kind of SCHEMA.properties.kind.enum) assert.ok(kinds.has(kind), kind);
  assert.ok(QUESTIONS.filter((q) => q.safe).length >= 3);
  assert.equal(QUESTIONS[3].after, 2);
});

let sqlite = null;
try {
  sqlite = require('node:sqlite');
} catch {
  // An older Node without node:sqlite skips the reference run.
}

test('the reference SQL finds every planted answer, and the guard refuses writes', { skip: sqlite == null }, () => {
  const db = trial.buildJournal();
  assert.ok(Object.keys(trial.REFERENCE).length >= 5);
  for (const [index, cards] of Object.entries(trial.REFERENCE)) {
    const spec = trial.QUESTIONS[index];
    const ran = cards.map((c) => ({ ...c, ...trial.runSql(db, c.sql) }));
    for (const c of ran) assert.equal(c.error, undefined, `${spec.question}: ${c.error}`);
    assert.ok(spec.check(ran, db), spec.question);
    const reply = { kind: 'answer', reason: 'none', cards: cards.map((c) => ({ title: 't', explain: 'e', ...c })) };
    assert.deepEqual(trial.verdict(spec, { answer: reply, reason: 'ok' }, ran, db), ['PASS', '']);
  }
  // A wrong answer fails the check.
  const wrong = [{ chart: trial.REFERENCE[4][0].chart, rows: [{ week_start: '2025-09-08' }] }];
  assert.equal(trial.QUESTIONS[4].check(wrong, db), false);
  for (const sql of [
    'DELETE FROM habits',
    'SELECT 1; DROP TABLE entries',
    'WITH x AS (SELECT 1) DELETE FROM habits',
    "ATTACH DATABASE ':memory:' AS x",
    'PRAGMA query_only = OFF',
  ]) {
    assert.ok(trial.runSql(db, sql).refused, sql);
  }
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM sqlite_master').get().n, 6);
});
