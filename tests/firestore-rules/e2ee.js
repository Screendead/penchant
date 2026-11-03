// The blob format of lib/crypto/journal_cipher.dart, for seeding the emulator
// and for rules fixtures: version(1) | nonce(12) | AES-256-GCM ct | tag(16),
// over a 2-byte length, the JSON, and zeros up to a bucket.
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export const BUCKETS = [64, 256, 1024, 4096];
export const MINIMUM_BUCKET = { vices: 256, activities: 64 };
export const OVERHEAD = 29;
export const BLOB_LENGTHS = BUCKETS.map((b) => b + OVERHEAD);

export const aad = ({ collection, docId, ownerID, viceID }) =>
  Buffer.from(`tracker:v1:${collection}:${docId}:${ownerID}${viceID == null ? '' : `:${viceID}`}`);

export function seal(dek, { collection, docId, ownerID, viceID, fields, bucket }) {
  const json = Buffer.from(JSON.stringify(fields));
  const size =
    bucket ?? BUCKETS.find((b) => b >= (MINIMUM_BUCKET[collection] ?? 64) && json.length + 2 <= b);
  if (!size) throw new Error(`fields too large: ${json.length}`);
  const padded = Buffer.alloc(size);
  padded.writeUInt16BE(json.length, 0);
  json.copy(padded, 2);
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', dek, nonce);
  cipher.setAAD(aad({ collection, docId, ownerID, viceID }));
  const ct = Buffer.concat([cipher.update(padded), cipher.final()]);
  return Buffer.concat([Buffer.from([1]), nonce, ct, cipher.getAuthTag()]);
}

export function open(dek, blob, ids) {
  const decipher = createDecipheriv('aes-256-gcm', dek, blob.subarray(1, 13));
  decipher.setAAD(aad(ids));
  decipher.setAuthTag(blob.subarray(blob.length - 16));
  const padded = Buffer.concat([decipher.update(blob.subarray(13, blob.length - 16)), decipher.final()]);
  return JSON.parse(padded.subarray(2, 2 + padded.readUInt16BE(0)).toString());
}
