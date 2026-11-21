'use strict';

// Runs a few made-up investigations through the analyst's prompt on Claude
// Opus 5.5, each step's queries on ask-journal-trial.js's made-up journal in
// memory, and prints every statement, its result as sent, and the finding with
// the server's verdict on it. Costs a few dollars at most: each investigation
// is up to 6 Opus calls.
// Run: ANTHROPIC_API_KEY=... node functions/tools/analyst-trial.js

const analyst = require('../analyst.js');
const { INPUT, buildJournal, runSql } = require('./ask-journal-trial.js');

const QUESTIONS = [
  'What changed in October?',
  'Why was December so heavy for wine?',
  'How did my smoking differ before and after the 8th of November?',
  'What stands out about my coffee on weekdays?',
  'Is there anything different about the weeks I drank less?',
];

// A cell as the phone sends it (cellText in lib/analyst/investigation.dart).
function cell(value) {
  if (value == null) return null;
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) return null;
    if (Number.isInteger(value)) return String(value);
    const s = value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
    return s === '-0' ? '0' : s;
  }
  const s = String(value);
  return s.length > analyst.LIMITS.cell ? s.slice(0, analyst.LIMITS.cell) : s;
}

// The phone's figures-only database refuses these columns; this made-up
// journal has them, so the trial refuses any statement naming them.
const FREE_TEXT = /\bnote\b|(?<!\bas\s+)\btext\b|(?:select|,|\.)\s*\*/i;

// One statement run and cut as the phone cuts it (cutResult).
function result(db, sql) {
  if (FREE_TEXT.test(sql)) return { refused: 'forbidden' };
  const ran = runSql(db, sql);
  if (!ran.rows) return { refused: ran.refused ? 'forbidden' : 'failed' };
  const columns = ran.rows.length > 0 ? Object.keys(ran.rows[0]).slice(0, analyst.LIMITS.columns) : [];
  const rows = ran.rows.slice(0, analyst.LIMITS.rows).map((r) => columns.map((c) => cell(r[c])));
  let truncated = ran.rows.length > analyst.LIMITS.rows;
  const sent = () => ({ columns, rows, truncated });
  while (rows.length > 0 && JSON.stringify(sent()).length > analyst.LIMITS.resultChars) {
    rows.pop();
    truncated = true;
  }
  return sent();
}

async function investigateOne(client, db, question) {
  const input = { ...INPUT, question, rounds: [] };
  for (let step = 1; step <= analyst.LIMITS.steps; step++) {
    const valid = analyst.validInput(input);
    if (valid == null) return { reason: 'invalid_input' };
    const started = Date.now();
    let message;
    try {
      message = await client.messages.stream(analyst.messageRequest(valid)).finalMessage();
    } catch (error) {
      return { reason: `api_error: ${error.message}` };
    }
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    const parsed = analyst.parseMessage(message);
    if (parsed.reason !== 'ok') {
      const reply = (message.content || []).filter((b) => b && b.type === 'text').map((b) => b.text).join('');
      console.log(`  step ${step} rejected (${parsed.why || parsed.reason}); reply:\n${reply}`);
      return { reason: parsed.reason, why: parsed.why };
    }
    const judged = analyst.judge(parsed.step, valid);
    console.log(`  step ${step} (${seconds} s, ${message.usage.input_tokens} in, ${message.usage.output_tokens} out)`);
    if (judged.reason !== 'ok') return { reason: judged.reason, why: judged.why, step: parsed.step };
    if (judged.step.kind === 'finding') return { reason: 'ok', step: judged.step };
    const results = judged.step.queries.map((q) => result(db, q.sql));
    judged.step.queries.forEach((q, i) => {
      console.log(`    ${q.title}: ${q.sql}`);
      console.log(`      -> ${JSON.stringify(results[i]).slice(0, 400)}`);
    });
    input.rounds.push({ queries: judged.step.queries, results });
  }
  return { reason: 'no_finding' };
}

async function main() {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('Set ANTHROPIC_API_KEY.');
    process.exit(1);
  }
  const Anthropic = require('@anthropic-ai/sdk');
  const client = new Anthropic({ timeout: 100000, maxRetries: 0 });
  const db = buildJournal();
  for (const question of QUESTIONS) {
    console.log(`\n${question}`);
    const { reason, why, step } = await investigateOne(client, db, question);
    if (step && step.kind === 'finding') {
      console.log(`  ${step.finding.headline}`);
      console.log(`  ${step.finding.body}`);
      console.log(`  rests on ${step.finding.rests_on.join(', ')}`);
    }
    console.log(`  => ${reason}${why ? ` (${why})` : ''}`);
  }
}

if (require.main === module) main();

module.exports = { QUESTIONS, cell };
