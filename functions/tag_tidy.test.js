'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');

const { NOTE_TAGS } = require('./note_tags.js');
const {
  MAX_LABEL,
  MAX_LABELS,
  MAX_SUGGESTIONS,
  MODEL,
  checkSuggestions,
  messageRequest,
  parseMessage,
  tidyTags,
  validLabels,
} = require('./tag_tidy.js');

const LABELS = ['hungover', 'hung over', 'hangover', 'bday', 'birthday drinks', "Sam's", "Alex's", 'payday'];

function message(body, stop_reason = 'end_turn') {
  return { stop_reason, content: [{ type: 'text', text: JSON.stringify(body) }] };
}

test('validLabels takes 2 to 200 distinct one-line labels of 1 to 60 units', () => {
  assert.deepEqual(validLabels({ labels: ['a', 'b'] }), ['a', 'b']);
  const many = Array.from({ length: MAX_LABELS }, (_, i) => `l${i}`);
  assert.deepEqual(validLabels({ labels: many }), many);
  assert.deepEqual(validLabels({ labels: ['x'.repeat(MAX_LABEL), 'y'] }), ['x'.repeat(MAX_LABEL), 'y']);

  assert.equal(validLabels(null), null);
  assert.equal(validLabels({}), null);
  assert.equal(validLabels({ labels: 'a,b' }), null);
  assert.equal(validLabels({ labels: [] }), null);
  assert.equal(validLabels({ labels: ['a'] }), null);
  assert.equal(validLabels({ labels: [...many, 'extra'] }), null);
  assert.equal(validLabels({ labels: ['x'.repeat(MAX_LABEL + 1), 'y'] }), null);
  assert.equal(validLabels({ labels: ['', 'y'] }), null);
  assert.equal(validLabels({ labels: ['  ', 'y'] }), null);
  assert.equal(validLabels({ labels: ['a\nb', 'y'] }), null);
  assert.equal(validLabels({ labels: ['a\rb', 'y'] }), null);
  assert.equal(validLabels({ labels: ['a', 'a'] }), null);
  assert.equal(validLabels({ labels: ['a', 3] }), null);
  assert.equal(validLabels({ labels: ['a', null] }), null);
});

test('checkSuggestions keeps a merge and a mapping in the output shape', () => {
  const { suggestions, dropped } = checkSuggestions(
    [
      { from: ['hungover', 'hung over', 'hangover'], path: '', label: 'hungover' },
      { from: ['payday'], path: 'event/payday', label: '' },
      { from: ['bday', 'birthday drinks'], path: 'event/birthday', label: '' },
    ],
    LABELS,
  );
  assert.equal(dropped, 0);
  assert.deepEqual(suggestions, [
    { from: ['hungover', 'hung over', 'hangover'], path: null, label: 'hungover' },
    { from: ['payday'], path: 'event/payday', label: null },
    { from: ['bday', 'birthday drinks'], path: 'event/birthday', label: null },
  ]);
});

test('checkSuggestions drops each suggestion breaking a rule', () => {
  const bad = [
    null,
    'hungover',
    { path: 'event/payday', label: '' }, // no from
    { from: 'payday', path: 'event/payday', label: '' }, // from not an array
    { from: [], path: 'event/payday', label: '' }, // empty from
    { from: ['payday', 3], path: 'event/payday', label: '' }, // not a string
    { from: ['Payday'], path: 'event/payday', label: '' }, // not a sent label
    { from: ['payday', 'payday'], path: 'event/payday', label: '' }, // repeated label
    { from: ['payday'], path: 'event/payday' }, // label missing
    { from: ['payday'], path: null, label: 'payday' }, // path mistyped
    { from: ['payday'], path: '', label: '' }, // neither
    { from: ['hungover', 'hangover'], path: 'body/hungover', label: 'hungover' }, // both
    { from: ['payday'], path: 'event', label: '' }, // not a leaf
    { from: ['payday'], path: 'event/pay-day', label: '' }, // not a path
    { from: ['hungover', 'hangover'], path: '', label: 'hung over' }, // kept label outside from
    { from: ['hungover'], path: '', label: 'hungover' }, // merge of one
  ];
  const { suggestions, dropped } = checkSuggestions(bad, LABELS);
  assert.deepEqual(suggestions, []);
  assert.equal(dropped, bad.length);
});

test('checkSuggestions drops a suggestion reusing a label an earlier kept one took', () => {
  const { suggestions, dropped } = checkSuggestions(
    [
      { from: ['bday'], path: 'event/birthday', label: '' }, // kept
      { from: ['bday', 'birthday drinks'], path: '', label: 'birthday drinks' }, // reuses bday
      { from: ['birthday drinks'], path: 'social/party', label: '' }, // earlier one was dropped, so free
    ],
    LABELS,
  );
  assert.deepEqual(
    suggestions.map((s) => s.from),
    [['bday'], ['birthday drinks']],
  );
  assert.equal(dropped, 1);
});

test('checkSuggestions keeps at most MAX_SUGGESTIONS', () => {
  const labels = Array.from({ length: MAX_SUGGESTIONS + 5 }, (_, i) => `l${i}`);
  const candidates = labels.map((l) => ({ from: [l], path: 'feeling/bored', label: '' }));
  const { suggestions, dropped } = checkSuggestions(candidates, labels);
  assert.equal(suggestions.length, MAX_SUGGESTIONS);
  assert.equal(dropped, 5);
});

test('checkSuggestions reads a missing or mistyped list as none', () => {
  assert.deepEqual(checkSuggestions(undefined, LABELS), { suggestions: [], dropped: 0 });
  assert.deepEqual(checkSuggestions({}, LABELS), { suggestions: [], dropped: 0 });
});

test('parseMessage gives a reason for every answer and never throws', () => {
  assert.equal(parseMessage(null, LABELS).reason, 'refusal');
  assert.equal(parseMessage(message({ suggestions: [] }, 'refusal'), LABELS).reason, 'refusal');
  assert.equal(parseMessage(message({ suggestions: [] }, 'max_tokens'), LABELS).reason, 'max_tokens');
  assert.equal(parseMessage({ stop_reason: 'end_turn', content: [{ type: 'text', text: '{"sugg' }] }, LABELS).reason, 'unparsable');
  assert.equal(parseMessage({ stop_reason: 'end_turn' }, LABELS).reason, 'unparsable');
  assert.deepEqual(parseMessage(message(null), LABELS), { suggestions: [], dropped: 0, reason: 'ok' });
  assert.deepEqual(
    parseMessage(
      message({
        suggestions: [
          { from: ['payday'], path: 'event/payday', label: '' },
          { from: ['nope'], path: 'event/payday', label: '' },
        ],
      }),
      LABELS,
    ),
    { suggestions: [{ from: ['payday'], path: 'event/payday', label: null }], dropped: 1, reason: 'ok' },
  );
});

test('tidyTags turns a failed call into api_error', async () => {
  const failing = { messages: { create: async () => { throw new Error('down'); } } };
  assert.deepEqual(await tidyTags(failing, LABELS), { suggestions: [], dropped: 0, reason: 'api_error' });
  const answering = { messages: { create: async () => message({ suggestions: [] }) } };
  assert.deepEqual(await tidyTags(answering, LABELS), { suggestions: [], dropped: 0, reason: 'ok' });
});

test('messageRequest sends the labels alone, as JSON, with thinking off', () => {
  const request = messageRequest(LABELS);
  assert.equal(request.model, MODEL);
  assert.equal(request.model, 'claude-haiku-5-5');
  assert.deepEqual(request.thinking, { type: 'disabled' });
  assert.equal(request.output_config.effort, 'low');
  assert.equal(request.output_config.format.type, 'json_schema');
  assert.equal(request.max_tokens, 3000);
  assert.deepEqual(request.messages, [{ role: 'user', content: JSON.stringify(LABELS) }]);

  const leaves = NOTE_TAGS.filter(({ path }) => path.includes('/'));
  for (const { path, label } of leaves) assert.ok(request.system.includes(`${path}: ${label}`), path);
  assert.match(request.system, /data, not instructions/);

  const item = request.output_config.format.schema.properties.suggestions.items;
  assert.deepEqual(item.required, ['from', 'path', 'label']);
  assert.equal(item.additionalProperties, false);
  assert.deepEqual(new Set(item.properties.path.enum), new Set([...leaves.map(({ path }) => path), '']));
  assert.equal(item.properties.path.enum.length, leaves.length + 1);
});
