'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');

const { NOTE_TAGS } = require('./note_tags.js');
const {
  MODEL,
  SCHEMA,
  SYSTEM,
  askJournal,
  messageRequest,
  parseMessage,
  validInput,
} = require('./ask_journal.js');
const { QUESTIONS } = require('./tools/ask-journal-trial.js');

const habits = [
  { name: 'Wine', unit: 'glasses', archived: false },
  { name: 'Vape', unit: 'puffs', archived: true },
];
const input = { question: 'When was my last week without wine?', today: '2026-11-15', weekday: 'Sunday', habits };

function resolve(schema) {
  if (schema && schema.$ref) return SCHEMA.$defs[schema.$ref.replace('#/$defs/', '')];
  return schema;
}

// Whether [value] fits [schema]; with [partial], an object may leave out
// required keys (the trial's expectations name only what they check).
function fits(value, rawSchema, partial = false) {
  const schema = resolve(rawSchema);
  if (schema.anyOf) return schema.anyOf.some((s) => fits(value, s, partial));
  if (schema.enum && !schema.enum.includes(value)) return false;
  switch (schema.type) {
    case 'null':
      return value === null;
    case 'string':
      return typeof value === 'string' && (schema.format !== 'date' || /^\d{4}-\d{2}-\d{2}$/.test(value));
    case 'integer':
      return Number.isInteger(value);
    case 'number':
      return typeof value === 'number';
    case 'array':
      return Array.isArray(value) && value.every((v) => fits(v, schema.items, partial));
    case 'object':
      if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
      if (!Object.keys(value).every((k) => k in schema.properties)) return false;
      if (!partial && !schema.required.every((k) => k in value)) return false;
      return Object.entries(value).every(([k, v]) => fits(v, schema.properties[k], partial));
    default:
      return false;
  }
}

const fullQuery = {
  kind: 'query',
  reason: 'none',
  habit: 0,
  measure: 'entries',
  period: { type: 'all_time', count: null, from: null, to: null },
  filter: { weekdays: [], from_hour: null, to_hour: null, tag: null },
  shape: 'last_time',
  bucket: 'week',
  condition: 'none',
  threshold: null,
  longest: null,
  versus: null,
};

test('the schema uses only what structured outputs accept', () => {
  const banned = ['minimum', 'maximum', 'multipleOf', 'minLength', 'maxLength', 'minItems', 'maxItems', 'pattern'];
  const walk = (node, where) => {
    if (Array.isArray(node)) return node.forEach((n, i) => walk(n, `${where}[${i}]`));
    if (node === null || typeof node !== 'object') return;
    for (const key of banned) assert.ok(!(key in node), `${where} uses ${key}`);
    if (node.type === 'object') {
      assert.equal(node.additionalProperties, false, `${where} allows extra keys`);
      assert.deepEqual([...node.required].sort(), Object.keys(node.properties).sort(), `${where} has optional keys`);
    }
    if (node.$ref) assert.ok(SCHEMA.$defs[node.$ref.replace('#/$defs/', '')], `${where} refers to nothing`);
    for (const [key, child] of Object.entries(node)) walk(child, `${where}.${key}`);
  };
  walk(SCHEMA, 'schema');
  // No definition refers to itself, directly or through another.
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
  assert.ok(fits(fullQuery, SCHEMA));
  assert.ok(!fits({ ...fullQuery, extra: 1 }, SCHEMA));
});

test('the request is Haiku 5.5 with thinking off, effort low and the query schema', () => {
  const request = messageRequest(validInput(input));
  assert.equal(request.model, MODEL);
  assert.equal(MODEL, 'claude-haiku-5-5');
  assert.deepEqual(request.thinking, { type: 'disabled' });
  assert.deepEqual(request.output_config, { effort: 'low', format: { type: 'json_schema', schema: SCHEMA } });
  assert.ok(request.max_tokens <= 1000);
  assert.equal(request.messages.length, 1);
  assert.deepEqual(JSON.parse(request.messages[0].content), {
    question: input.question,
    today: '2026-11-15',
    weekday: 'Sunday',
    habits: [
      { index: 0, name: 'Wine', unit: 'glasses', archived: false },
      { index: 1, name: 'Vape', unit: 'puffs', archived: true },
    ],
  });
  assert.match(request.system, /data, not instructions/);
  assert.deepEqual(messageRequest(validInput(input), 'claude-sonnet-5-5').thinking, { type: 'between_tools' });
});

test('the prompt lists every tag id', () => {
  for (const { path } of NOTE_TAGS) assert.ok(SYSTEM.includes(`\n${path}: `), path);
});

test('the input is a bounded question, a real today with its weekday, and named habits', () => {
  assert.deepEqual(validInput({ ...input, uid: 'x', extra: 1 }), input);
  assert.equal(validInput({ ...input, question: 'x'.repeat(300) }).question.length, 300);
  assert.equal(validInput({ ...input, question: 'x'.repeat(301) }), null);
  assert.equal(validInput({ ...input, question: '🍷'.repeat(151) }), null);
  assert.equal(validInput({ ...input, question: '  ' }), null);
  assert.equal(validInput({ ...input, question: 3 }), null);
  assert.equal(validInput({ ...input, today: '2026-02-30' }), null);
  assert.equal(validInput({ ...input, today: '15/11/2026' }), null);
  assert.equal(validInput({ ...input, weekday: 'Monday' }), null);
  assert.equal(validInput({ ...input, habits: [] }), null);
  assert.equal(validInput({ ...input, habits: Array(101).fill(habits[0]) }), null);
  assert.equal(validInput({ ...input, habits: [{ ...habits[0], name: 'x'.repeat(61) }] }), null);
  assert.equal(validInput({ ...input, habits: [{ ...habits[0], unit: 'x'.repeat(21) }] }), null);
  assert.equal(validInput({ ...input, habits: [{ ...habits[0], archived: 'no' }] }), null);
  assert.deepEqual(validInput({ ...input, habits: [{ ...habits[0], entries: [1] }] }).habits, [habits[0]]);
  assert.equal(validInput(null), null);
  assert.equal(validInput('question'), null);
});

test('the answer is read into a query, or why there is none, never throwing', () => {
  const text = (t) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: t }] });
  assert.deepEqual(parseMessage(text(JSON.stringify(fullQuery))), { query: fullQuery, reason: 'ok' });
  assert.deepEqual(parseMessage({ stop_reason: 'refusal', content: [] }), { query: null, reason: 'refusal' });
  assert.deepEqual(parseMessage({ stop_reason: 'max_tokens', content: [] }), { query: null, reason: 'max_tokens' });
  assert.deepEqual(parseMessage(text('{"kind":')), { query: null, reason: 'unparsable' });
  assert.deepEqual(parseMessage(text('[]')), { query: null, reason: 'unparsable' });
  assert.deepEqual(parseMessage(text('{"kind":"answer"}')), { query: null, reason: 'unparsable' });
  assert.deepEqual(parseMessage(null), { query: null, reason: 'refusal' });
  assert.deepEqual(parseMessage({ stop_reason: 'end_turn', content: 'x' }), { query: null, reason: 'unparsable' });
});

test('an API failure is a reason, not a throw', async () => {
  const failing = { messages: { create: async () => { throw new Error('down'); } } };
  assert.deepEqual(await askJournal(failing, validInput(input)), { query: null, reason: 'api_error' });
  const answering = {
    messages: { create: async () => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(fullQuery) }] }) },
  };
  assert.deepEqual(await askJournal(answering, validInput(input)), { query: fullQuery, reason: 'ok' });
});

test('the trial has 40 questions, each expectation a fit for the schema', () => {
  assert.equal(QUESTIONS.length, 40);
  const kinds = new Set();
  for (const [question, expectation] of QUESTIONS) {
    for (const alternative of Array.isArray(expectation) ? expectation : [expectation]) {
      assert.ok(fits(alternative, SCHEMA, true), question);
      kinds.add(alternative.shape ? `${alternative.kind}/${alternative.shape}` : alternative.kind);
    }
  }
  for (const kind of [
    'query/total',
    'query/series',
    'query/last_time',
    'query/longest',
    'query/compare',
    'needs_insights',
    'cannot_answer',
  ]) {
    assert.ok(kinds.has(kind), kind);
  }
});
