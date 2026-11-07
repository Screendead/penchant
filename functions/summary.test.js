'use strict';

const assert = require('node:assert/strict');
const { describe, it } = require('node:test');

const { summarise, typicalQuantity } = require('./summary.js');

describe('typicalQuantity', () => {
  it('takes the middle of an odd count', () => {
    assert.equal(typicalQuantity([30, 10, 20]), 20);
  });

  it('averages the two middles of an even count', () => {
    assert.equal(typicalQuantity([1, 2, 3, 10]), 2.5);
  });

  it('ignores zero and negative amounts', () => {
    assert.equal(typicalQuantity([0, -4, 3]), 3);
  });

  it('is 1 with nothing positive', () => {
    assert.equal(typicalQuantity([]), 1);
    assert.equal(typicalQuantity([0]), 1);
  });

  it('is not moved by one unusual entry', () => {
    assert.equal(typicalQuantity([2, 2, 2, 2, 200]), 2);
  });
});

describe('summarise', () => {
  it('is empty with no entries', () => {
    assert.deepEqual(summarise([]), {});
  });

  it('keeps each habit on its own', () => {
    assert.deepEqual(
      summarise([
        { viceID: 'a', quantity: 10 },
        { viceID: 'b', quantity: 1 },
        { viceID: 'a', quantity: 30 },
        { viceID: 'a', quantity: 20 },
      ]),
      { a: { typical: 20, count: 3 }, b: { typical: 1, count: 1 } },
    );
  });

  it('drops entries without a usable vice or amount', () => {
    assert.deepEqual(
      summarise([
        { viceID: 'a', quantity: 2 },
        { viceID: 'a', quantity: 0 },
        { viceID: 'a', quantity: '5' },
        { viceID: 'a', quantity: Number.NaN },
        { viceID: '', quantity: 3 },
        { quantity: 3 },
        { viceID: 'a' },
      ]),
      { a: { typical: 2, count: 1 } },
    );
  });

  it('accepts decimal amounts', () => {
    assert.deepEqual(summarise([{ viceID: 'a', quantity: 0.5 }, { viceID: 'a', quantity: 1.5 }]), {
      a: { typical: 1, count: 2 },
    });
  });
});
