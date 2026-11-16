'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const fixture = require('./letter_fixture.json');
const {
  LETTER_DENIED_TERMS,
  MAX_CHARS,
  MODEL,
  NUMBER_WORDS,
  SCHEMA,
  checkLetter,
  checkPassage,
  contextOf,
  messageRequest,
  parseMessage,
  validInput,
  writeLetter,
} = require('./letter.js');

const payload = () => JSON.parse(JSON.stringify(fixture.payload));

const goodSections = () => [
  { heading: 'What you wrote about most', body: 'You logged Wine on 2 days, 3.5 glasses in all.' },
  { heading: 'What shifted', body: 'In August you wrote “needed it after the meeting, 3 hours late”.' },
  { heading: 'Day notes', body: 'Day notes: 1; entry notes: 2.' },
];

const goodLetter = () => ({
  sections: goodSections(),
  toTest: [{ title: 'Evenings after work', why: 'Your notes suggest the walk home matters.' }],
  quotes: ['needed it after the meeting, 3 hours late'],
});

test('the model id is Opus 5.5', () => {
  assert.equal(MODEL, 'claude-opus-5-5');
});

test('validInput accepts the fixture and copies it exactly', () => {
  const input = validInput(payload());
  assert.notEqual(input, null);
  assert.deepEqual(input, fixture.payload);
});

test('validInput keeps only the known keys at every level', () => {
  const p = payload();
  p.uid = 'abc';
  p.period.id = 'x';
  p.entries[0].id = 'doc1';
  p.entries[0].ownerID = 'abc';
  p.entries[0].health = { steps: '9000' };
  p.dayNotes[0].id = 'abc_2026-09-14';
  p.figures.places = [];
  p.figures.habits[0].id = 'v1';
  p.figures.notes.locked = '3';
  p.figures.tags[0].path = 'work/long-day';
  p.figures.months[0].id = 'm';
  const input = validInput(p);
  assert.deepEqual(Object.keys(input), ['period', 'entries', 'dayNotes', 'figures']);
  assert.deepEqual(Object.keys(input.period), ['from', 'to', 'months', 'shortened']);
  assert.deepEqual(Object.keys(input.entries[0]), ['date', 'time', 'habit', 'amount', 'unit', 'tags', 'urge', 'note', 'followUp']);
  assert.deepEqual(Object.keys(input.entries[0].followUp), ['question', 'answer']);
  assert.deepEqual(Object.keys(input.entries[1]), ['date', 'time', 'habit', 'amount', 'unit', 'tags']);
  assert.deepEqual(Object.keys(input.dayNotes[0]), ['date', 'text', 'tags']);
  assert.deepEqual(Object.keys(input.figures), ['habits', 'months', 'notes', 'tags']);
  assert.deepEqual(Object.keys(input.figures.habits[0]), ['habit', 'unit', 'total', 'entries', 'days']);
  assert.deepEqual(Object.keys(input.figures.months[0]), ['month', 'habits']);
  assert.deepEqual(Object.keys(input.figures.months[0].habits[0]), ['habit', 'total', 'entries', 'days']);
  assert.deepEqual(Object.keys(input.figures.notes), ['entryNotes', 'dayNotes', 'followUps']);
  assert.deepEqual(Object.keys(input.figures.tags[0]), ['tag', 'count']);
  assert.deepEqual(input, fixture.payload);
});

test('validInput refuses what is out of bounds', () => {
  const cases = {
    'over the budget': (p) => {
      p.dayNotes = Array.from({ length: 120 }, (_, i) => ({
        date: '2026-09-14',
        text: `${i} ${'x'.repeat(1990)}`,
        tags: [],
      }));
      assert.ok(JSON.stringify(p).length > MAX_CHARS);
    },
    'an entry outside the period': (p) => {
      p.entries[0].date = '2026-08-15';
    },
    'a day note after the period': (p) => {
      p.dayNotes[0].date = '2026-11-17';
    },
    'an unknown urge': (p) => {
      p.entries[0].urge = '5';
    },
    'a note over 500': (p) => {
      p.entries[0].note = 'x'.repeat(501);
    },
    'months 2': (p) => {
      p.period.months = 2;
    },
    'no entries and no day notes': (p) => {
      p.entries = [];
      p.dayNotes = [];
    },
    'a figure as a number': (p) => {
      p.figures.habits[0].total = 3.5;
    },
    'a figure with a comma': (p) => {
      p.figures.habits[0].total = '1,000';
    },
    'a mistyped month': (p) => {
      p.figures.months[0].month = '2026-08';
    },
    'an impossible date': (p) => {
      p.period.from = '2026-02-30';
    },
    'a follow-up without an answer': (p) => {
      p.entries[0].followUp = { question: 'Why?' };
    },
  };
  for (const [name, change] of Object.entries(cases)) {
    const p = payload();
    change(p);
    assert.equal(validInput(p), null, name);
  }
  assert.equal(validInput(null), null);
  assert.equal(validInput('x'), null);
});

test('the term lists equal the fixture the device test reads', () => {
  assert.deepEqual(LETTER_DENIED_TERMS, fixture.terms);
  assert.deepEqual(NUMBER_WORDS, fixture.numberWords);
  for (const allowed of ['count', 'amount', 'units', 'fewer', 'suggest', 'why']) {
    assert.ok(!LETTER_DENIED_TERMS.includes(allowed), allowed);
  }
  for (const denied of ['should', 'problem', 'addiction', 'healthy', 'too much', 'cut down', 'concerning']) {
    assert.ok(LETTER_DENIED_TERMS.includes(denied), denied);
  }
});

test('checkPassage gives each fixture case its reason', () => {
  const context = contextOf(validInput(payload()));
  for (const { text, expect } of fixture.cases) {
    assert.equal(checkPassage(text, context), expect, text);
  }
});

test('checkLetter keeps a letter that keeps every rule', () => {
  const result = checkLetter(goodLetter(), validInput(payload()));
  assert.equal(result.reason, 'ok');
  assert.deepEqual(result.withheld, []);
  assert.deepEqual(result.letter, { ...goodLetter(), withheld: 0 });
});

test('checkLetter withholds a section that breaks a rule', () => {
  const answer = goodLetter();
  answer.sections.push({ heading: 'Evenings', body: 'You should look at evenings.' });
  const result = checkLetter(answer, validInput(payload()));
  assert.equal(result.reason, 'ok');
  assert.equal(result.letter.sections.length, 3);
  assert.equal(result.letter.withheld, 1);
  assert.deepEqual(result.withheld, [{ kind: 'section', index: 3, reason: 'term:should' }]);
});

test('checkLetter refuses a reply without 3 to 5 sections', () => {
  const answer = goodLetter();
  answer.sections = answer.sections.slice(0, 2);
  assert.equal(checkLetter(answer, validInput(payload())).reason, 'sections');
  const many = goodLetter();
  many.sections = [...goodSections(), ...goodSections()];
  assert.equal(checkLetter(many, validInput(payload())).reason, 'sections');
});

test('checkLetter shows nothing when under 2 sections survive', () => {
  const answer = goodLetter();
  answer.sections = [
    goodSections()[0],
    { heading: 'Totals', body: 'Wine came to 4 glasses.' },
    { heading: 'Evenings', body: 'This looks like a problem.' },
    { heading: 'Notes', body: 'You wrote "needed it badly".' },
  ];
  const result = checkLetter(answer, validInput(payload()));
  assert.equal(result.reason, 'too_few_sections');
  assert.equal(result.letter, null);
  assert.deepEqual(
    result.withheld.map((w) => w.reason),
    ['number:4', 'term:problem', 'quote'],
  );
});

test('checkLetter drops a bad suggestion and cuts them at 3', () => {
  const answer = goodLetter();
  answer.toTest = [
    { title: 'Evenings', why: 'You need to cut down.' },
    { title: 'Walks', why: 'Your notes suggest the walk home matters.' },
    { title: 'Mornings', why: 'Your notes mention “walk home with Sam”.' },
    { title: 'Weekends', why: 'Day notes: 1; entry notes: 2.' },
    { title: 'Late nights', why: 'Your notes suggest the walk home matters.' },
  ];
  const result = checkLetter(answer, validInput(payload()));
  assert.equal(result.reason, 'ok');
  assert.deepEqual(result.letter.toTest.map((t) => t.title), ['Walks', 'Mornings']);
  assert.equal(result.letter.withheld, 1);
  assert.deepEqual(result.withheld, [{ kind: 'toTest', index: 0, reason: 'term:need to' }]);
});

test('checkLetter drops quotes that are not in a note', () => {
  const answer = goodLetter();
  answer.quotes = ['needed it after the meeting', 'something never written', 'my boss should have listened', 7];
  const result = checkLetter(answer, validInput(payload()));
  assert.deepEqual(result.letter.quotes, ['needed it after the meeting', 'my boss should have listened']);
});

test('checkLetter withholds a mistyped section', () => {
  const answer = goodLetter();
  answer.sections.push({ heading: 'Empty', body: '' });
  const result = checkLetter(answer, validInput(payload()));
  assert.deepEqual(result.withheld, [{ kind: 'section', index: 3, reason: 'mistyped' }]);
});

test('messageRequest is one Opus 5.5 call with structured output', () => {
  const input = validInput(payload());
  const request = messageRequest(input);
  assert.equal(request.model, 'claude-opus-5-5');
  assert.equal(request.max_tokens, 16000);
  assert.deepEqual(request.output_config, { effort: 'medium', format: { type: 'json_schema', schema: SCHEMA } });
  assert.ok(!('thinking' in request));
  assert.ok(!('fallbacks' in request));
  assert.ok(!('tool_choice' in request));
  assert.ok(!('tools' in request));
  assert.equal(request.messages.length, 1);
  assert.equal(request.messages[0].role, 'user');
  assert.equal(request.messages[0].content, JSON.stringify(input));
  assert.equal(SCHEMA.additionalProperties, false);
});

test('parseMessage reads by block type and never throws', () => {
  assert.deepEqual(parseMessage({ stop_reason: 'refusal', content: [] }), { answer: null, reason: 'refusal' });
  assert.deepEqual(parseMessage(null), { answer: null, reason: 'refusal' });
  assert.deepEqual(parseMessage({ stop_reason: 'max_tokens', content: [] }), { answer: null, reason: 'max_tokens' });
  const ok = parseMessage({
    stop_reason: 'end_turn',
    content: [
      { type: 'thinking', thinking: '' },
      { type: 'text', text: JSON.stringify(goodLetter()) },
    ],
  });
  assert.deepEqual(ok, { answer: goodLetter(), reason: 'ok' });
  assert.equal(parseMessage({ stop_reason: 'end_turn', content: [{ type: 'text', text: '{nope' }] }).reason, 'unparsable');
  assert.equal(parseMessage({ stop_reason: 'end_turn', content: [{ type: 'text', text: '[1]' }] }).reason, 'unparsable');
  assert.equal(parseMessage({ stop_reason: 'end_turn', content: [] }).reason, 'unparsable');
});

test('writeLetter streams the request and checks the reply', async () => {
  const input = validInput(payload());
  let sent = null;
  const client = {
    messages: {
      stream(request) {
        sent = request;
        return {
          finalMessage: async () => ({
            stop_reason: 'end_turn',
            content: [{ type: 'text', text: JSON.stringify(goodLetter()) }],
          }),
        };
      },
    },
  };
  const result = await writeLetter(client, input);
  assert.deepEqual(sent, messageRequest(input));
  assert.equal(result.reason, 'ok');
  assert.equal(result.letter.sections.length, 3);
});

test('writeLetter answers api_error when the call fails', async () => {
  const throwing = {
    messages: {
      stream() {
        throw new Error('network');
      },
    },
  };
  assert.deepEqual(await writeLetter(throwing, validInput(payload())), { letter: null, reason: 'api_error', withheld: [] });
  const rejecting = {
    messages: {
      stream: () => ({ finalMessage: async () => Promise.reject(new Error('timeout')) }),
    },
  };
  assert.equal((await writeLetter(rejecting, validInput(payload()))).reason, 'api_error');
});
