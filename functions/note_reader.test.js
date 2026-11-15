'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const { NOTE_TAGS } = require('./note_tags.js');
const {
  DailyCap,
  LEAF_PATHS,
  MODEL,
  checkTags,
  messageRequest,
  parseMessage,
  readNote,
  validNote,
} = require('./note_reader.js');

// Each TriggerNode('id', 'label', ...) in the Dart tree, as paths in order.
function dartTree() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'lib', 'data', 'trigger_tree.dart'), 'utf8');
  const tree = source.slice(source.indexOf('const List<TriggerNode> triggerTree'));
  const node = /TriggerNode\(\s*'([^']+)',\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*(,\s*icon:)?/g;
  const out = [];
  let area = null;
  for (const match of tree.matchAll(node)) {
    const label = match[2].slice(1, -1).replace(/\\(.)/g, '$1');
    if (match[3]) area = match[1];
    out.push({ path: match[3] ? match[1] : `${area}/${match[1]}`, label });
  }
  return out;
}

test('the tag list is the Dart starter tree', () => {
  const dart = dartTree();
  assert.equal(dart.length, 47);
  assert.deepEqual(NOTE_TAGS, dart);
});

test('a note is a string of 1 to 500 UTF-16 units, not all white space', () => {
  assert.equal(validNote({ note: 'pub with Sam' }), 'pub with Sam');
  assert.equal(validNote({ note: 'x'.repeat(500) }), 'x'.repeat(500));
  assert.equal(validNote({ note: 'x'.repeat(501) }), null);
  // Each emoji is two UTF-16 units.
  assert.equal(validNote({ note: '🍺'.repeat(251) }), null);
  assert.equal(validNote({ note: '' }), null);
  assert.equal(validNote({ note: '  \n' }), null);
  assert.equal(validNote({ note: 3 }), null);
  assert.equal(validNote({}), null);
  assert.equal(validNote(null), null);
});

test('only listed paths with quotes found in the note survive, at most four', () => {
  const note = 'Boss tore into the roadmap, went to the pub with Sam.';
  const { tags, dropped } = checkTags(
    [
      { path: 'work/hard-talk', quote: 'Boss tore into the roadmap' },
      { path: 'work/made-up', quote: 'roadmap' },
      { path: 'place/bar', quote: 'went to the bar' },
      { path: 'place/bar', quote: 'the pub' },
      { path: 'social/friends', quote: 'with Sam' },
      { path: 'social/friends', quote: 'Sam' },
      { path: 'feeling/stressed', quote: '' },
      { path: 'work', quote: 'Boss' },
      { path: 'social/alone', quote: 'BOSS' },
      { path: 'feeling/low', quote: 'tore' },
      { path: 'place/commute', quote: 'went' },
      null,
    ],
    note,
  );
  assert.deepEqual(tags, [
    { path: 'work/hard-talk', quote: 'Boss tore into the roadmap' },
    { path: 'place/bar', quote: 'the pub' },
    { path: 'social/friends', quote: 'with Sam' },
    { path: 'feeling/low', quote: 'tore' },
  ]);
  assert.equal(dropped, 8);
  assert.deepEqual(checkTags('nonsense', note), { tags: [], dropped: 0 });
});

test('the request is Haiku 5.5 at its fastest, with a schema of listed paths', () => {
  const request = messageRequest('a note');
  assert.equal(request.model, MODEL);
  assert.equal(MODEL, 'claude-haiku-5-5');
  assert.deepEqual(request.thinking, { type: 'disabled' });
  assert.equal(request.output_config.effort, 'low');
  assert.equal(request.output_config.format.type, 'json_schema');
  const item = request.output_config.format.schema.properties.tags.items;
  assert.deepEqual(new Set(item.properties.path.enum), LEAF_PATHS);
  assert.equal(LEAF_PATHS.size, 40);
  assert.deepEqual(request.messages, [{ role: 'user', content: 'a note' }]);
  assert.ok(!('temperature' in request));
  // Nothing but the note and the tag list reaches the model.
  for (const { path: leaf } of NOTE_TAGS.filter(({ path: p }) => p.includes('/'))) {
    assert.ok(request.system.includes(leaf));
  }
});

const text = (value) => ({
  stop_reason: 'end_turn',
  content: [{ type: 'text', text: JSON.stringify(value) }],
});

test('a refusal, a cut-off or unreadable answer gives no tags and a reason', () => {
  const note = 'beer in the garden';
  assert.deepEqual(parseMessage({ stop_reason: 'refusal', content: [] }, note), {
    tags: [],
    dropped: 0,
    reason: 'refusal',
  });
  assert.equal(parseMessage({ stop_reason: 'max_tokens', content: [] }, note).reason, 'max_tokens');
  assert.equal(
    parseMessage({ stop_reason: 'end_turn', content: [{ type: 'text', text: '{"tags":' }] }, note).reason,
    'unparsable',
  );
  assert.deepEqual(parseMessage(text({ tags: [{ path: 'place/outdoors', quote: 'in the garden' }] }), note), {
    tags: [{ path: 'place/outdoors', quote: 'in the garden' }],
    dropped: 0,
    reason: 'ok',
  });
});

test('readNote sends one request and turns an API failure into a reason', async () => {
  const sent = [];
  const ok = {
    messages: {
      create: async (request) => {
        sent.push(request);
        return text({ tags: [{ path: 'routine/habit', quote: 'just what I do' }] });
      },
    },
  };
  const note = 'Had a cigarette, just what I do.';
  assert.deepEqual(await readNote(ok, note), {
    tags: [{ path: 'routine/habit', quote: 'just what I do' }],
    dropped: 0,
    reason: 'ok',
  });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].messages[0].content, note);

  const failing = {
    messages: {
      create: async () => {
        throw new Error('overloaded');
      },
    },
  };
  assert.deepEqual(await readNote(failing, note), { tags: [], dropped: 0, reason: 'api_error' });
});

test('the cap allows 60 calls a uid a UTC day', () => {
  const cap = new DailyCap();
  const morning = new Date('2026-11-15T08:00:00Z');
  for (let i = 0; i < 60; i++) assert.equal(cap.take('a', morning), true);
  assert.equal(cap.take('a', morning), false);
  assert.equal(cap.take('b', morning), true);
  assert.equal(cap.take('a', new Date('2026-11-16T00:00:01Z')), true);
});
