'use strict';

// Whether a callable's caller may use Claude: signed in with a verified
// email, never a guest. [auth] is the request's auth context.
function verifiedCaller(auth) {
  const token = auth && auth.token;
  if (token == null || typeof token !== 'object') return false;
  const provider = token.firebase && token.firebase.sign_in_provider;
  if (provider === 'anonymous') return false;
  return token.email_verified === true;
}

module.exports = { verifiedCaller };
