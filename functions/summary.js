'use strict';

// The same middle as typicalQuantity in lib/data/dial_layout.dart, so a stored
// typical and the app's own fallback agree on the same entries.
function typicalQuantity(quantities) {
  const sorted = quantities.filter((q) => q > 0).sort((a, b) => a - b);
  if (sorted.length === 0) {
    return 1;
  }
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

// Activities as { viceID, quantity }. Only viceID and quantity are read: under
// end-to-end encryption habit names and units are sealed, amounts are not.
function summarise(activities) {
  const byVice = new Map();
  for (const { viceID, quantity } of activities) {
    if (typeof viceID !== 'string' || viceID === '') continue;
    if (typeof quantity !== 'number' || !Number.isFinite(quantity) || quantity <= 0) continue;
    let list = byVice.get(viceID);
    if (!list) {
      list = [];
      byVice.set(viceID, list);
    }
    list.push(quantity);
  }
  const vices = {};
  for (const [viceID, quantities] of byVice) {
    vices[viceID] = { typical: typicalQuantity(quantities), count: quantities.length };
  }
  return vices;
}

module.exports = { summarise, typicalQuantity };
