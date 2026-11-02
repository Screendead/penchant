# populateFirestore.js hardcodes a production UID, cannot dedupe, and needs a credential no clone has

**Severity:** low

The script hardcodes a live Firebase Auth UID as the owner of every document it creates, a fixed roster of five vices and thirty days of randomly generated activity, with no arguments, environment variables or upsert logic, so every run blindly adds new documents and re-running duplicates data. That UID is a real user identifier permanently committed to history, tying the script and everything it wrote to one identifiable account.

It also requires `admin/privateKey.json`, a service-account credential absent from the repository and its entire history, so the `require` call would fail on a fresh clone.

## Evidence

- `admin/populateFirestore.js:3` — `const serviceAccount = require('./privateKey.json');`
- `admin/populateFirestore.js:19` — `const ownerID = '1J6xVvHsFWYLPd5VPmI2t4nuGNo1';`
- `admin/populateFirestore.js:26` — `const docRef = await vicesRef.add({`
- **`ls -la admin/privateKey.json`** → `ls: admin/privateKey.json: No such file or directory`
