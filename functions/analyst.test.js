'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');

const analyst = require('./analyst.js');
const fixture = require('./analyst_fixture.json');
const trial = require('./tools/analyst-trial.js');

const clone = (v) => JSON.parse(JSON.stringify(v));
const input = () => clone(fixture.input);
const card = fixture.input.rounds[0].queries[0];
const noFinding = { headline: '', body: '', rests_on: [] };
const text = (t) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: t }] });

test('each shared case gives the reason the device gives', () => {
  const context = analyst.contextOf(analyst.validInput(input()));
  for (const { text: passage, expect } of fixture.cases) {
    assert.equal(analyst.checkPassage(passage, context), expect, passage);
  }
});

test('validInput keeps the known keys and the bounds', () => {
  const valid = analyst.validInput({ ...input(), extra: 'x' });
  assert.deepEqual(Object.keys(valid), ['question', 'today', 'weekday', 'habits', 'rounds']);
  assert.deepEqual(valid.rounds, fixture.input.rounds);
  assert.ok(analyst.validInput({ ...input(), rounds: [] }));
});

test('validInput refuses anything out of shape or too big', () => {
  const round = fixture.input.rounds[0];
  const rows = (n, width = 1, cell = 'x') => ({
    columns: Array.from({ length: width }, (_, i) => `c${i}`),
    rows: Array.from({ length: n }, () => Array.from({ length: width }, () => cell)),
    truncated: false,
  });
  const bad = [
    { ...input(), rounds: Array(analyst.MAX_ROUNDS + 1).fill(round) },
    { ...input(), rounds: [{ ...round, results: [round.results[0]] }] },
    { ...input(), rounds: [{ queries: [], results: [] }] },
    { ...input(), rounds: [{ queries: [card], results: [rows(51)] }] },
    { ...input(), rounds: [{ queries: [card], results: [rows(1, 21)] }] },
    { ...input(), rounds: [{ queries: [card], results: [{ columns: ['a'], rows: [['x'.repeat(201)]], truncated: false }] }] },
    { ...input(), rounds: [{ queries: [card], results: [{ columns: ['a'], rows: [[3]], truncated: false }] }] },
    { ...input(), rounds: [{ queries: [card], results: [{ columns: ['a', 'b'], rows: [['x']], truncated: false }] }] },
    { ...input(), rounds: [{ queries: [card], results: [rows(50, 20, 'x'.repeat(10))] }] },
    { ...input(), rounds: [{ queries: [card], results: [{ refused: 'SQLITE said no' }] }] },
    { ...input(), rounds: [{ queries: [card], results: [{ refused: 'forbidden', why: 'x' }] }] },
    { ...input(), rounds: [{ queries: [{ ...card, sql: '' }], results: [{ refused: 'failed' }] }] },
    { ...input(), question: '' },
    { ...input(), rounds: undefined },
    { ...input(), question: 'x'.repeat(301) },
  ];
  for (const data of bad) assert.equal(analyst.validInput(data), null, JSON.stringify(data).slice(0, 200));
});

test('validStep reads queries and findings, and nothing between', () => {
  assert.ok(analyst.validStep({ kind: 'queries', queries: [card], finding: noFinding }));
  const f = analyst.validStep({ kind: 'finding', queries: [], finding: { headline: ' H ', body: 'B', rests_on: [1] } });
  assert.deepEqual(f.finding, { headline: 'H', body: 'B', rests_on: [1] });
  for (const bad of [
    { kind: 'queries', queries: [], finding: noFinding },
    { kind: 'finding', queries: [], finding: { headline: 'H', body: 'B', rests_on: [] } },
    { kind: 'finding', queries: [], finding: { headline: 'H'.repeat(analyst.LIMITS.headline + 1), body: 'B', rests_on: [1] } },
    { kind: 'finding', queries: [], finding: { headline: 'H', body: 'B', rests_on: ['1'] } },
    { kind: 'other', queries: [], finding: noFinding },
  ]) {
    assert.equal(analyst.validStep(bad), null, JSON.stringify(bad).slice(0, 120));
  }
});

test('validStep drops what is harmlessly outside the shape', () => {
  const four = analyst.validStep({ kind: 'queries', queries: [card, card, card, card], finding: noFinding });
  assert.equal(four.queries.length, analyst.LIMITS.queries);
  const withFinding = analyst.validStep({ kind: 'queries', queries: [card], finding: { headline: 'H', body: 'B', rests_on: [1] } });
  assert.deepEqual(withFinding.finding, { headline: '', body: '', rests_on: [] });
  const withCards = analyst.validStep({ kind: 'finding', queries: [card], finding: { headline: 'H', body: 'B', rests_on: [1] } });
  assert.deepEqual(withCards.queries, []);
  assert.equal(withCards.finding.headline, 'H');
});

test('parseMessage says which rule a rejected reply broke, with nothing of the reply', () => {
  const finding = (f) => ({ kind: 'finding', queries: [], finding: { headline: 'H', body: 'B', rests_on: [1], ...f } });
  const cases = [
    ['not json', 'json'],
    [{ kind: 'queries' }, 'shape'],
    [{ kind: 'other', queries: [], finding: noFinding }, 'shape'],
    [{ kind: 'queries', queries: [], finding: noFinding }, 'cards'],
    [{ kind: 'queries', queries: [{ ...card, sql: 'x'.repeat(4001) }], finding: noFinding }, 'cards'],
    [finding({ headline: 'H'.repeat(analyst.LIMITS.headline + 1) }), 'headline_length'],
    [finding({ headline: ' ' }), 'headline_length'],
    [finding({ body: 'B'.repeat(analyst.LIMITS.body + 1) }), 'body_length'],
    [finding({ rests_on: [] }), 'rests_on'],
  ];
  for (const [reply, why] of cases) {
    const parsed = analyst.parseMessage(text(typeof reply === 'string' ? reply : JSON.stringify(reply)));
    assert.deepEqual(parsed, { step: null, reason: 'unparsable', why }, why);
  }
  assert.ok(analyst.validStep(finding({ headline: 'H'.repeat(analyst.LIMITS.headline), body: 'B'.repeat(analyst.LIMITS.body) })));
});

test('judge withholds a finding the transcript does not bear out', () => {
  const valid = analyst.validInput(input());
  const finding = (headline, restsOn = [1]) => ({ kind: 'finding', queries: [], finding: { headline, body: 'B.', rests_on: restsOn } });
  assert.equal(analyst.judge(finding('Wine came to 64 entries in October.'), valid).reason, 'ok');
  assert.deepEqual(analyst.judge(finding('Wine rose by 23.'), valid), { step: null, reason: 'checks', why: 'number:23' });
  assert.equal(analyst.judge(finding('Wine.', [2]), valid).why, 'rests_on');
  assert.equal(analyst.judge(finding('Wine.', [4]), valid).why, 'rests_on');
  assert.equal(analyst.judge(finding('Wine.', [1, 1]), valid).why, 'rests_on');
  assert.equal(analyst.judge(finding('Work led to more Wine.'), valid).why, 'cause:led to');
});

test('the last step must conclude', () => {
  const valid = analyst.validInput({ ...input(), rounds: Array(analyst.MAX_ROUNDS).fill(fixture.input.rounds[0]) });
  const step = { kind: 'queries', queries: [card], finding: noFinding };
  assert.equal(analyst.judge(step, valid).reason, 'no_finding');
  assert.equal(JSON.parse(analyst.messageRequest(valid).messages[0].content).last_step, true);
  assert.equal(analyst.judge(step, analyst.validInput(input())).reason, 'ok');
});

test('the request is Opus with structured output, numbering every statement', () => {
  const request = analyst.messageRequest(analyst.validInput(input()));
  assert.equal(request.model, 'claude-opus-5-5');
  assert.equal(request.thinking, undefined);
  assert.equal(request.output_config.effort, 'medium');
  assert.equal(request.output_config.format.schema, analyst.SCHEMA);
  const content = JSON.parse(request.messages[0].content);
  assert.deepEqual(Object.keys(content), ['question', 'today', 'weekday', 'habits', 'statements', 'last_step']);
  assert.deepEqual(content.statements.map((s) => s.n), [1, 2, 3]);
  assert.deepEqual(content.statements[1].result, { refused: 'forbidden' });
  assert.equal(content.last_step, false);
  assert.match(analyst.SYSTEM, /refused/);
});

test('parseMessage reads the step or why not', () => {
  const step = { kind: 'queries', queries: [card], finding: noFinding };
  assert.deepEqual(analyst.parseMessage(text(JSON.stringify(step))), { step, reason: 'ok' });
  assert.equal(analyst.parseMessage({ stop_reason: 'refusal', content: [] }).reason, 'refusal');
  assert.equal(analyst.parseMessage({ stop_reason: 'max_tokens', content: [] }).reason, 'max_tokens');
  assert.equal(analyst.parseMessage(text('not json')).reason, 'unparsable');
  assert.equal(analyst.parseMessage(text('{"kind":"queries"}')).reason, 'unparsable');
});

test('investigate streams one call and never throws', async () => {
  const step = { kind: 'finding', queries: [], finding: { headline: 'Wine came to 64 entries.', body: 'B.', rests_on: [1] } };
  const ok = { messages: { stream: () => ({ finalMessage: async () => text(JSON.stringify(step)) }) } };
  assert.equal((await analyst.investigate(ok, analyst.validInput(input()))).reason, 'ok');
  const down = {
    messages: {
      stream: () => ({
        finalMessage: async () => {
          throw new Error('down');
        },
      }),
    },
  };
  assert.deepEqual(await analyst.investigate(down, analyst.validInput(input())), { step: null, reason: 'api_error' });
});

test('the trial formats cells as the device does', () => {
  assert.equal(trial.cell(3), '3');
  assert.equal(trial.cell(2.5), '2.5');
  assert.equal(trial.cell(61.538), '61.54');
  assert.equal(trial.cell(-0.001), '0');
  assert.equal(trial.cell(null), null);
  assert.ok(trial.QUESTIONS.length >= 3);
});

test('a card past Ask\'s bounds is dropped, the rest kept, and none left is cards', () => {
  const wide = { ...card, chart: { type: 'table', x: 'month', y: ['a', 'b', 'c', 'd', 'e', 'f'], series: '', x_kind: 'category' } };
  const kept = analyst.validStep({ kind: 'queries', queries: [card, wide, card], finding: noFinding });
  assert.deepEqual(kept.queries, [card, card]);
  const four = analyst.validStep({ kind: 'queries', queries: [wide, card, card, card, card], finding: noFinding });
  assert.equal(four.queries.length, analyst.LIMITS.queries);
  const none = analyst.parseMessage(text(JSON.stringify({ kind: 'queries', queries: [wide], finding: noFinding })));
  assert.deepEqual(none, { step: null, reason: 'unparsable', why: 'cards' });
  assert.ok(analyst.SYSTEM.includes('y at most 4 numeric columns'));
});

// Results as the trial of 2026-11-16 sent them, cut to what the cases need.
const withResults = (...results) => ({
  ...input(),
  rounds: [{ queries: results.map(() => card), results }],
});
const judged = (data, body) =>
  analyst.judge({ kind: 'finding', queries: [], finding: { headline: 'Wine.', body, rests_on: [1] } }, analyst.validInput(data));

test('a count word stands when a result counted it, and not otherwise', () => {
  const byHabit = {
    columns: ['habit', 'september', 'october'],
    rows: [['Wine', '37', '37'], ['Cigarettes', '84', '82'], ['Coffee', '56', '57']],
    truncated: false,
  };
  assert.equal(judged(withResults(byHabit), 'Totals were close for all three habits.').reason, 'ok');
  assert.equal(judged(withResults(byHabit), 'Totals were close for all four habits.').why, 'number_word:four');
  assert.equal(judged(withResults(byHabit), 'Totals were close for all 3 habits.').why, 'number:3');
  assert.equal(judged(withResults({ ...byHabit, truncated: true }), 'All three habits.').why, 'number_word:three');
  assert.equal(judged(withResults(byHabit), 'All three habits, twice as many.').why, 'number_word:twice');
});

test('a clock time H:00 stands when a cell held the hour whole, and not otherwise', () => {
  const byHour = {
    columns: ['hour', 'period', 'pct'],
    rows: [['18', 'December', '11.3'], ['20', 'December', '46.8'], ['8', 'December', '2']],
    truncated: false,
  };
  assert.equal(judged(withResults(byHour), 'At 20:00 came 46.8% of it, and 2% at 08:00.').reason, 'ok');
  assert.equal(judged(withResults(byHour), 'At 21:00 came 46.8% of it.').why, 'number:21:00');
  assert.equal(judged(withResults(byHour), 'At 20:30 came 46.8% of it.').why, 'number:20:30');
  // Day 18 of a date is no hour, nor is a threshold written only in the SQL.
  const byDay = { columns: ['day', 'cigarettes'], rows: [['2026-10-18', '2']], truncated: false };
  assert.equal(judged(withResults(byDay), 'From 18:00 on came 2.').why, 'number:18:00');
});

test('distinct values ignore nulls, as on the device', () => {
  const rows = {
    columns: ['habit', 'hour', 'day'],
    rows: [['Wine', '20', '2026-10-18'], ['Coffee', '8', '2026-10-18'], ['Tea', '20', null]],
    truncated: false,
  };
  assert.equal(judged(withResults(rows), 'All three habits peaked at 20:00 or 08:00.').reason, 'ok');
  assert.equal(judged(withResults(rows), 'Two days.').reason, 'ok');
});

test('a whole-number cell lets its count word stand, and a quoted whole cell passes as words', () => {
  const periods = {
    columns: ['period', 'days', 'cigarettes'],
    rows: [['1 all earlier days', '425', '1054'], ['2 eight days before', '8', '33'], ['3 from 8 Nov', '8', '20']],
    truncated: false,
  };
  assert.equal(judged(withResults(periods), 'Against 33 in the eight days just before.').reason, 'ok');
  assert.equal(judged(withResults(periods), 'Against 33 in the nine days just before.').why, 'number_word:nine');
  const tags = {
    columns: ['label', 'december_glasses'],
    rows: [['With friends', '12'], ['Work drinks', '12'], ['Stressed', '8'], ['after work', '8']],
    truncated: false,
  };
  assert.equal(judged(withResults(tags), '"Work drinks" 12 and "after work" 8.').reason, 'ok');
  assert.equal(judged(withResults(tags), '"work drinks" 12.').why, 'quote');
  assert.equal(judged(withResults(tags), '"Work" 12.').why, 'quote');
  const literal = { columns: ['x'], rows: [['Work led to more Wine']], truncated: false };
  assert.equal(judged(withResults(literal), '"Work led to more Wine".').why, 'cause:led to');
});
