# actions/checkout is three majors behind and all three actions are pinned to mutable tags

**Severity:** medium

Both workflows pin `actions/checkout` at v4 against a current major of v7, whose release notes describe changed defaults around fork pull-request checkouts that block common pwn-request patterns, so the repository does not carry that later hardening. That action plus the Flutter action and the Firebase hosting-deploy action are each referenced by a floating major tag their publishers can repoint at any time, so the exact code these jobs run is not fixed by the repository content alone.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:13` — `- uses: actions/checkout@v4`
- `.github/workflows/firebase-hosting-pull-request.yml:15` — `- uses: actions/checkout@v4`
- `.github/workflows/firebase-hosting-merge.yml:14` — `- uses: subosito/flutter-action@v2`
- `.github/workflows/firebase-hosting-merge.yml:24` — `- uses: FirebaseExtended/action-hosting-deploy@v0`
