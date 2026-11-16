# Penchant backup file, format 1

Written by `BackupFile.write` and read by `BackupFile.open` (`lib/backup/backup_file.dart`). Byte offsets from 0;
integers big-endian.

| Bytes | Field |
| --- | --- |
| 0-7 | Magic, ASCII `PNCHNTBK` |
| 8 | Format version, `1`. A larger number is refused as "saved by a newer version". |
| 9-12 | `H`, the header's length in bytes (at most 4096) |
| 13 to 13+H | Header: UTF-8 JSON, below |
| next `bodyLength` bytes | Body: one `Sealer` envelope, below |
| last 32 bytes | SHA-256 of every byte before it |

## Header (plaintext, authenticated)

```json
{"createdAt": 1763290000000, "uid": "…", "keyID": "…", "wrapped": "<base64, 61 bytes>", "bodyLength": 8221}
```

- `createdAt`: when the backup was made, milliseconds since the epoch (UTC). Shown before the recovery key is asked
  for, so the person can tell copies apart.
- `uid`: the account it was saved from. Needed: the wrapped key's associated data is
  `penchant:v1:journal-key-wrap:<uid>`, and day notes' ids (and so their envelopes' associated data) contain it. It is
  a random Firebase id, no personal data; whoever holds the file learns which account it came from.
- `keyID` and `wrapped`: exactly the `keyID` and `wrapped` of `keys/{uid}` when the backup was made. `wrapped` is the
  journal key sealed under the 128-bit recovery key (AES-128-GCM), the same 61 bytes the server holds.
- `bodyLength`: the body's length, so a cut-short file is told apart from a changed one. The file's size shows it
  anyway.

Nothing else about the journal is in plaintext: no counts, names or dates of entries.

## Body (encrypted and authenticated)

`version(1) | nonce(12) | ciphertext | tag(16)`: `Sealer.sealFile` under the journal key, AES-256-GCM with a fresh
random 96-bit nonce. Associated data: every byte from offset 0 to the end of the header (magic, version, header length
and header), so changing any of them makes the body fail to open.

The plaintext is padded by `Sealer.padFile`: a 4-byte length, the payload, then zeros to the smallest power of two of
at least 4096 bytes. The file's size reveals only that power of two.

The payload is UTF-8 JSON:

```json
{"collections": {"vices": [{"id": "…", "data": {…}}], "activities": […], "dayNotes": […], "urges": […]}}
```

One entry per collection of `Account.ownedCollections`, each document exactly as the server held it: its plaintext
fields and, for a sealed document, its `sealed` envelope unopened (still bound to its original path). Values: strings,
booleans, null, ints and doubles as themselves (Dart writes every double with a point or exponent, so an int stays an
int); a map as `{"$map": {…}}`, a timestamp as `{"$timestamp": [seconds, nanoseconds]}`, bytes as
`{"$bytes": "<base64>"}`. Any other Firestore type refuses the backup.

One envelope, not a chunked stream: `padFile` takes up to 2^31 bytes and AES-GCM's limit for one message is about
64 GiB, while a journal of 20,000 entries is a few megabytes. No new construction is needed.

## Opening, in order

Each step fails closed with its own message; nothing is written before the last passes.

1. Magic: else "not a Penchant backup". A file shorter than the fixed part that starts with it is "incomplete".
2. Version: larger is "newer format"; smaller or zero is "not a backup".
3. Header parses; file length equals 13 + H + `bodyLength` + 32: shorter is "incomplete", longer "damaged".
4. Checksum: else "damaged". It is unkeyed, so it catches accidents, not someone who rewrites it.
5. Unwrap `wrapped` with the recovery key and `uid`: else "wrong recovery key". A changed `uid` or `wrapped` with the
   checksum rewritten looks exactly the same to AES-GCM.
6. `keyIDOf(key) == keyID`: else "key mismatch".
7. Open the body: else "modified".

## Restore

The backup's journal key stays in memory. Each document's envelope is opened with it at its original path
(`collection/oldID`) and the fields are sealed again, unread and whole, under the signed-in account's own journal key
at the new path. Ids are new and the same on every run: a day note's is `{uid}_{day}` as the rules require; any other's
is 20 characters from SHA-256 of `penchant:v1:restore-id:{source uid}\n{collection}\n{old id}\n{new uid}`.
