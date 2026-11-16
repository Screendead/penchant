'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { verifiedCaller } = require('./caller.js');

test('a guest is refused', () => {
  assert.equal(verifiedCaller({ token: { firebase: { sign_in_provider: 'anonymous' } } }), false);
  // A linked guest's old token could carry a verified claim beside anonymous.
  assert.equal(
    verifiedCaller({ token: { email_verified: true, firebase: { sign_in_provider: 'anonymous' } } }),
    false,
  );
});

test('an unverified email is refused', () => {
  assert.equal(verifiedCaller({ token: { email_verified: false, firebase: { sign_in_provider: 'password' } } }), false);
  assert.equal(verifiedCaller({ token: { email_verified: 'true', firebase: { sign_in_provider: 'password' } } }), false);
});

test('a verified email is let through', () => {
  assert.equal(verifiedCaller({ token: { email_verified: true, firebase: { sign_in_provider: 'password' } } }), true);
});

test('missing token fields are refused', () => {
  assert.equal(verifiedCaller(undefined), false);
  assert.equal(verifiedCaller({}), false);
  assert.equal(verifiedCaller({ token: {} }), false);
  assert.equal(verifiedCaller({ token: { firebase: {} } }), false);
  assert.equal(verifiedCaller({ token: null }), false);
});
