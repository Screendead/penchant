'use strict';

const assert = require('node:assert/strict');
const { describe, it } = require('node:test');

const {
  LOOKUP_BATCH,
  MAX_CANDIDATES,
  MIN_RUN_GAP_MS,
  chunk,
  distinctOwners,
  missingUids,
  reconcile,
  runCleanup,
} = require('./cleanup.js');

const DAY = 24 * 60 * 60 * 1000;
const t0 = new Date('2026-11-07T04:30:00Z');
const later = (ms) => new Date(t0.getTime() + ms);

// Admin getUsers over a fixed set of existing uids, recording each call.
function fakeAuth(existing) {
  const calls = [];
  const getUsers = async (identifiers) => {
    calls.push(identifiers.map((id) => id.uid));
    return {
      users: identifiers.filter(({ uid }) => existing.has(uid)).map(({ uid }) => ({ uid })),
      notFound: identifiers.filter(({ uid }) => !existing.has(uid)),
    };
  };
  return { getUsers, calls };
}

// A fetchPage over a list, `size` uids a page.
function pages(list, size) {
  const calls = [];
  const fetchPage = async (cursor) => {
    calls.push(cursor);
    const start = cursor ?? 0;
    const end = Math.min(start + size, list.length);
    return { uids: list.slice(start, end), cursor: end, done: end >= list.length };
  };
  return { fetchPage, calls };
}

describe('chunk', () => {
  it('splits at the batch size and keeps the last partial batch', () => {
    const ids = (n) => Array.from({ length: n }, (_, i) => `u${i}`);
    assert.deepEqual(chunk(ids(100), LOOKUP_BATCH).map((b) => b.length), [100]);
    assert.deepEqual(chunk(ids(101), LOOKUP_BATCH).map((b) => b.length), [100, 1]);
    assert.deepEqual(chunk(ids(250), LOOKUP_BATCH).map((b) => b.length), [100, 100, 50]);
    assert.deepEqual(chunk([], LOOKUP_BATCH), []);
  });
});

describe('distinctOwners', () => {
  it('pages to the end and dedupes', async () => {
    const { fetchPage, calls } = pages(['a', 'b', 'a', 'c', 'b'], 2);
    const result = await distinctOwners(fetchPage, 10);
    assert.deepEqual([...result.uids].sort(), ['a', 'b', 'c']);
    assert.equal(result.truncated, false);
    assert.deepEqual(calls, [null, 2, 4]);
  });

  it('stops at the page cap and says so', async () => {
    const { fetchPage, calls } = pages(['a', 'b', 'c', 'd', 'e'], 2);
    const result = await distinctOwners(fetchPage, 2);
    assert.deepEqual([...result.uids], ['a', 'b', 'c', 'd']);
    assert.equal(result.truncated, true);
    assert.equal(calls.length, 2);
  });

  it('drops owner ids Auth could never hold', async () => {
    const { fetchPage } = pages(['a', '', 42, null, 'x'.repeat(129), 'x'.repeat(128)], 10);
    const result = await distinctOwners(fetchPage, 10);
    assert.deepEqual([...result.uids], ['a', 'x'.repeat(128)]);
    assert.equal(result.invalid, 4);
  });
});

describe('missingUids', () => {
  it('asks in batches of at most 100 and reports only the uids Auth lacks', async () => {
    const uids = Array.from({ length: 250 }, (_, i) => `u${i}`);
    const existing = new Set(uids.filter((_, i) => i % 2 === 0));
    const { getUsers, calls } = fakeAuth(existing);
    const missing = await missingUids(getUsers, new Set(uids));
    assert.deepEqual(calls.map((c) => c.length), [100, 100, 50]);
    assert.equal(missing.size, 125);
    for (const uid of existing) assert.equal(missing.has(uid), false);
  });

  it('never calls a returned user missing, even if Auth also lists it as not found', async () => {
    const getUsers = async () => ({ users: [{ uid: 'alive' }], notFound: [{ uid: 'alive' }, { uid: 'gone' }] });
    assert.deepEqual([...(await missingUids(getUsers, new Set(['alive', 'gone'])))], ['gone']);
  });

  it('ignores not-found uids it did not ask about', async () => {
    const getUsers = async () => ({ users: [], notFound: [{ uid: 'asked' }, { uid: 'stranger' }] });
    assert.deepEqual([...(await missingUids(getUsers, new Set(['asked'])))], ['asked']);
  });

  it('propagates an Auth failure instead of reading it as missing', async () => {
    const getUsers = async () => {
      throw new Error('quota');
    };
    await assert.rejects(missingUids(getUsers, new Set(['a'])), /quota/);
  });
});

describe('reconcile', () => {
  it('makes a first-time missing uid a candidate, not a deletion', () => {
    const { toDelete, next } = reconcile(null, new Set(['a']), t0);
    assert.deepEqual(toDelete, []);
    assert.deepEqual(next, { candidates: ['a'], scannedAt: t0 });
  });

  it('deletes a uid missing on two consecutive runs a day apart', () => {
    const previous = { candidates: ['a', 'b'], scannedAt: t0 };
    const { toDelete, next } = reconcile(previous, new Set(['a', 'c']), later(DAY));
    assert.deepEqual(toDelete, ['a']);
    assert.deepEqual(next.candidates, ['a', 'c']);
  });

  it('drops a candidate that exists again', () => {
    const previous = { candidates: ['a'], scannedAt: t0 };
    const { toDelete, next } = reconcile(previous, new Set(), later(DAY));
    assert.deepEqual(toDelete, []);
    assert.deepEqual(next.candidates, []);
  });

  it('does not count a second run within the gap as the next day', () => {
    const previous = { candidates: ['a'], scannedAt: t0 };
    const { toDelete, next } = reconcile(previous, new Set(['a']), later(MIN_RUN_GAP_MS - 1));
    assert.deepEqual(toDelete, []);
    assert.equal(next, null);
    assert.deepEqual(reconcile(previous, new Set(['a']), later(MIN_RUN_GAP_MS)).toDelete, ['a']);
  });

  it('caps the stored candidates', () => {
    const missing = new Set(Array.from({ length: MAX_CANDIDATES + 5 }, (_, i) => `u${i}`));
    assert.equal(reconcile(null, missing, t0).next.candidates.length, MAX_CANDIDATES);
  });
});

describe('runCleanup', () => {
  function world({ existing, owners, state = null }) {
    const auth = fakeAuth(new Set(existing));
    const io = {
      sources: [['vices', pages(owners, 2).fetchPage, 10]],
      getUsers: auth.getUsers,
      state,
      counted: [],
      deleted: [],
      logs: [],
      readState: async () => io.state,
      writeState: async (next) => {
        io.state = next;
      },
      countOwned: async (uid) => {
        io.counted.push(uid);
        return { vices: 1 };
      },
      deleteOwned: async (uid) => {
        io.deleted.push(uid);
      },
      log: (level, message, fields) => io.logs.push({ level, message, fields }),
    };
    return io;
  }

  it('in dry run never deletes, however many runs confirm a uid', async () => {
    const io = world({ existing: ['alive'], owners: ['alive', 'gone'] });
    for (let day = 0; day < 3; day++) {
      await runCleanup(io, { dryRun: true, now: later(day * DAY), maxDeletes: 50 });
    }
    assert.deepEqual(io.deleted, []);
    assert.deepEqual(io.counted, ['gone', 'gone']);
    const wouldDelete = io.logs.filter((l) => l.message === 'Orphan cleanup would delete');
    assert.deepEqual(wouldDelete.map((l) => l.fields.uid), ['gone', 'gone']);
  });

  it('deletes only a uid missing twice, and never one that exists', async () => {
    const io = world({ existing: ['alive'], owners: ['alive', 'gone'] });
    const first = await runCleanup(io, { dryRun: false, now: t0, maxDeletes: 50 });
    assert.deepEqual(first.acted, []);
    assert.deepEqual(io.state.candidates, ['gone']);
    const second = await runCleanup(io, { dryRun: false, now: later(DAY), maxDeletes: 50 });
    assert.deepEqual(second.acted, ['gone']);
    assert.deepEqual(io.deleted, ['gone']);
  });

  it('leaves the state alone when run again too soon', async () => {
    const io = world({ existing: [], owners: ['gone'], state: { candidates: ['gone'], scannedAt: t0 } });
    const result = await runCleanup(io, { dryRun: false, now: later(60 * 60 * 1000), maxDeletes: 50 });
    assert.equal(result.skipped, true);
    assert.deepEqual(io.deleted, []);
    assert.deepEqual(io.state, { candidates: ['gone'], scannedAt: t0 });
  });

  it('defers confirmed uids past the per-run cap to the next run', async () => {
    const io = world({
      existing: [],
      owners: ['a', 'b', 'c'],
      state: { candidates: ['a', 'b', 'c'], scannedAt: t0 },
    });
    const result = await runCleanup(io, { dryRun: false, now: later(DAY), maxDeletes: 2 });
    assert.deepEqual(result.acted, ['a', 'b']);
    assert.deepEqual(io.state.candidates, ['a', 'b', 'c']);
  });

  it('writes no state when the Auth lookup fails', async () => {
    const io = world({ existing: [], owners: ['gone'], state: { candidates: ['gone'], scannedAt: t0 } });
    io.getUsers = async () => {
      throw new Error('unavailable');
    };
    await assert.rejects(runCleanup(io, { dryRun: false, now: later(DAY), maxDeletes: 50 }), /unavailable/);
    assert.deepEqual(io.deleted, []);
    assert.deepEqual(io.state, { candidates: ['gone'], scannedAt: t0 });
  });

  it('logs uids and counts, never document contents', async () => {
    const io = world({ existing: [], owners: ['gone'], state: { candidates: ['gone'], scannedAt: t0 } });
    await runCleanup(io, { dryRun: true, now: later(DAY), maxDeletes: 50 });
    for (const { fields } of io.logs) {
      for (const key of Object.keys(fields)) {
        assert.ok(
          ['dryRun', 'uid', 'counts', 'owners', 'scanned', 'missing', 'confirmed', 'deferred', 'candidates', 'lastRun'].includes(key),
          key,
        );
      }
    }
  });
});
