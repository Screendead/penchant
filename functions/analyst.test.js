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
    { kind: 'queries', queries: [card, card, card, card], finding: noFinding },
    { kind: 'queries', queries: [], finding: noFinding },
    { kind: 'queries', queries: [card], finding: { headline: 'H', body: '', rests_on: [] } },
    { kind: 'finding', queries: [card], finding: { headline: 'H', body: 'B', rests_on: [1] } },
    { kind: 'finding', queries: [], finding: { headline: 'H', body: 'B', rests_on: [] } },
    { kind: 'finding', queries: [], finding: { headline: 'H'.repeat(121), body: 'B', rests_on: [1] } },
    { kind: 'finding', queries: [], finding: { headline: 'H', body: 'B', rests_on: ['1'] } },
    { kind: 'other', queries: [], finding: noFinding },
  ]) {
    assert.equal(analyst.validStep(bad), null, JSON.stringify(bad).slice(0, 120));
  }
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
