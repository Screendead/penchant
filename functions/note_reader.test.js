'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const { NOTE_TAGS } = require('./note_tags.js');
const {
  DENIED_TERMS,
  DailyCap,
  LEAF_PATHS,
  MAX_QUESTION,
  MAX_QUOTE,
  MODEL,
  checkQuestion,
  checkTags,
  messageRequest,
  parseMessage,
  readNote,
  validNote,
  wantsQuestion,
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
  assert.equal(dart.length, 185);
  assert.deepEqual(NOTE_TAGS, dart);
});

test('a note is a string of 1 to 2000 UTF-16 units, not all white space', () => {
  assert.equal(validNote({ note: 'pub with Sam' }), 'pub with Sam');
  assert.equal(validNote({ note: 'x'.repeat(2000) }), 'x'.repeat(2000));
  assert.equal(validNote({ note: 'x'.repeat(2001) }), null);
  // Each emoji is two UTF-16 units.
  assert.equal(validNote({ note: '🍺'.repeat(1001) }), null);
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
  assert.equal(LEAF_PATHS.size, 174);
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

// The follow-up question, asked for in the same call as the tags.
const NOTE = 'Rough one. Boss tore into the roadmap, went straight to the pub with Sam.';
const QUOTE = 'went straight to the pub';

test('without question the request is the tags-only one, unchanged', () => {
  const plain = messageRequest(NOTE);
  assert.deepEqual(messageRequest(NOTE, { question: false }), plain);
  assert.equal(plain.max_tokens, 400);
  assert.deepEqual(Object.keys(plain.output_config.format.schema.properties), ['tags']);
  assert.ok(!plain.system.includes('question'));
});

test('with question the same single request also asks for question and quote', () => {
  const asked = messageRequest(NOTE, { question: true });
  const plain = messageRequest(NOTE);
  assert.equal(asked.model, plain.model);
  assert.deepEqual(asked.thinking, plain.thinking);
  assert.equal(asked.output_config.effort, plain.output_config.effort);
  assert.ok(asked.max_tokens > plain.max_tokens);
  const schema = asked.output_config.format.schema;
  assert.deepEqual(schema.required, ['tags', 'question', 'quote']);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.tags, plain.output_config.format.schema.properties.tags);
  for (const key of ['question', 'quote']) {
    assert.deepEqual(schema.properties[key], { anyOf: [{ type: 'string' }, { type: 'null' }] });
  }
  assert.ok(asked.system.startsWith(plain.system));
  for (const rule of ['at most 140 characters', 'Never about amounts', 'Never advice', 'never ask "why"', 'Never mention being an AI']) {
    assert.ok(asked.system.includes(rule), rule);
  }
  assert.deepEqual(asked.messages, plain.messages);
});

test('wantsQuestion takes only a literal true', () => {
  assert.equal(wantsQuestion({ note: 'x', question: true }), true);
  for (const data of [null, {}, { question: 'true' }, { question: 1 }]) assert.equal(wantsQuestion(data), false);
});

test('a question that keeps every rule passes with its quote', () => {
  assert.deepEqual(checkQuestion('Was that already the plan this morning?', QUOTE, NOTE), {
    question: { question: 'Was that already the plan this morning?', quote: QUOTE },
    drop: null,
  });
  assert.equal(checkQuestion('  Who else was there?  ', QUOTE, NOTE).question.question, 'Who else was there?');
});

test('each rule code can check drops the question', () => {
  const drop = (q, quote = QUOTE, note = NOTE) => checkQuestion(q, quote, note).drop;
  assert.equal(drop(null), 'none_given');
  assert.equal(drop(''), 'none_given');
  assert.equal(drop(42), 'mistyped');
  assert.equal(drop('Who was there?', null), 'mistyped');
  assert.equal(drop(`Who ${'was '.repeat(40)}there?`), 'too_long');
  assert.equal(drop(`W${'h'.repeat(MAX_QUESTION - 2)}?`), null);
  assert.equal(drop(`W${'h'.repeat(MAX_QUESTION - 1)}?`), 'too_long');
  assert.equal(drop('Who was\nthere?'), 'line_break');
  assert.equal(drop('Tell me who was there.'), 'no_question_mark');
  assert.equal(drop('Who was there? Where?'), 'several_questions');
  assert.equal(drop('Who was there?? '), 'several_questions');
  assert.equal(drop('Was it after 6pm?'), 'digit');
  assert.equal(drop('Who was there?', ''), 'quote_length');
  assert.equal(drop('Who was there?', 'x'.repeat(MAX_QUOTE + 1), 'x'.repeat(MAX_QUOTE + 1)), 'quote_length');
  assert.equal(drop('Who was there?', 'went to the pub'), 'quote_not_in_note');
  assert.equal(drop('Who was there?', 'Went straight to the pub'), 'quote_not_in_note');
});

test('the deny-list drops amounts, advice, judgement, labels, the future, stopping and the model', () => {
  const cases = {
    'How much did you have?': 'how much',
    'How many were there?': 'how many',
    'Do you think you should stop?': 'should',
    'Do you need to talk to someone?': 'need to',
    'Have you tried to cut down?': 'cut down',
    'Was that too much for you?': 'too much',
    'Is this a problem for you?': 'problem',
    'Do you worry about it?': 'worry',
    'Was that a healthy choice?': 'healthy',
    'Do you feel addicted?': 'addicted',
    'Was it a bad night?': 'bad',
    'Are you proud of yourself?': 'proud',
    'Is that okay with you?': 'okay',
    'Will you do it differently next time?': 'will you',
    'What would make tomorrow different?': 'tomorrow',
    'Have you thought about quitting?': 'quitting',
    'Why did you go?': 'why',
    'As an AI, may I ask who was there?': 'ai',
    'Did Claude get that right?': 'claude',
  };
  for (const [question, term] of Object.entries(cases)) {
    assert.equal(checkQuestion(question, QUOTE, NOTE).drop, `term:${term}`, question);
  }
  // Whole words only: "said" holds "ai", "stopped by" is not about stopping.
  assert.equal(checkQuestion('What had Sam said just before?', QUOTE, NOTE).drop, null);
  assert.equal(checkQuestion('Where were you when Sam asked?', QUOTE, NOTE).drop, null);
  for (const term of ['should', 'problem', 'addiction', 'dependence', 'cut down', 'too much', 'healthy', 'worry']) {
    assert.ok(DENIED_TERMS.includes(term), term);
  }
});

test('asked for a question, the answer carries it beside the same tags', () => {
  const answer = {
    tags: [{ path: 'social/friends', quote: 'with Sam' }],
    question: 'Was that already the plan this morning?',
    quote: QUOTE,
  };
  const tagsOnly = parseMessage(text(answer), NOTE);
  assert.deepEqual(Object.keys(tagsOnly), ['tags', 'dropped', 'reason']);
  const asked = parseMessage(text(answer), NOTE, { question: true });
  assert.deepEqual(asked.tags, tagsOnly.tags);
  assert.equal(asked.reason, 'ok');
  assert.deepEqual(asked.question, { question: answer.question, quote: QUOTE });
  assert.equal(asked.questionDrop, null);
});

test('a missing, null or failing question never loses the tags', () => {
  const tags = [{ path: 'social/friends', quote: 'with Sam' }];
  for (const extra of [{}, { question: null, quote: null }, { question: 'Why did you go?', quote: QUOTE },
    { question: 'Who was there?', quote: 'not in the note' }, { question: { nested: true }, quote: QUOTE }]) {
    const result = parseMessage(text({ tags, ...extra }), NOTE, { question: true });
    assert.deepEqual(result.tags, tags, JSON.stringify(extra));
    assert.equal(result.reason, 'ok');
    assert.equal(result.question, null);
    assert.ok(typeof result.questionDrop === 'string');
  }
  const refused = parseMessage({ stop_reason: 'refusal', content: [] }, NOTE, { question: true });
  assert.deepEqual(refused, { tags: [], dropped: 0, reason: 'refusal', question: null, questionDrop: 'no_answer' });
});

test('readNote asks for the question in its one call only when told to', async () => {
  const sent = [];
  const client = {
    messages: {
      create: async (request) => {
        sent.push(request);
        return text({ tags: [], question: 'Who else was there?', quote: QUOTE });
      },
    },
  };
  const asked = await readNote(client, NOTE, { question: true });
  assert.equal(sent.length, 1);
  assert.deepEqual(asked.question, { question: 'Who else was there?', quote: QUOTE });
  const plain = await readNote(client, NOTE);
  assert.equal(sent.length, 2);
  assert.ok(!('question' in plain));
  assert.ok(!('question' in sent[1].output_config.format.schema.properties));
  const failing = { messages: { create: async () => { throw new Error('down'); } } };
  assert.deepEqual(await readNote(failing, NOTE, { question: true }), {
    tags: [], dropped: 0, reason: 'api_error', question: null, questionDrop: 'no_answer',
  });
});
