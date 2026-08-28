# Haka Firebase Backend

Haka uses Firebase Authentication, Realtime Database, second-generation Cloud Functions, App Check, Cloud Messaging, and the Local Emulator Suite. Android is a client of this backend; heart, membership, totals, decay, and streak state remain server-authoritative.

## Runtime and region

- Node.js: **22** for local development, CI, and deployed Functions
- Java: 21 recommended for the Realtime Database emulator
- Functions region: **`asia-south1`**
- Functions capacity: 256 MiB, zero minimum instances, two maximum callable instances

The region is fixed in `functions/src/index.ts`. Configure the Android Functions SDK for `asia-south1`. Changing region after production launch is a migration, not a routine configuration edit.

Use the repository declaration before installing or testing:

```bash
nvm install
nvm use
node --version
```

The version must begin with `v22`. Firebase also declares `nodejs22` in `firebase.json`, and CI uses Node 22.

## Firebase projects and aliases

Use separate projects where practical:

```text
dev      Haka Development
staging  Haka Staging
prod     Haka Production
```

Real project IDs are deliberately not committed. Copy the example and configure aliases locally:

```bash
cp .firebaserc.example .firebaserc
firebase login
firebase use --add
firebase projects:list
```

`.firebaserc` is ignored by Git. Confirm the active project before every deploy:

```bash
firebase use
```

Use the Development project first. Never point emulator tests at Staging or Production.

## Firebase console setup

For each remote environment:

1. Create the Firebase project.
2. Upgrade to Blaze only because Cloud Functions deployment requires billing. Blaze does not guarantee a charge; it also does not guarantee a zero bill.
3. Create Realtime Database in a region compatible with the chosen Functions region and expected users.
4. Enable Authentication providers:
   - Anonymous for fast onboarding;
   - Google for durable Android identity;
   - optionally email/password for controlled testing.
5. Register the Android application using the correct environment-specific package name.
6. Add the Android signing certificate SHA-256 fingerprint.
7. Register App Check with Play Integrity, but delay enforcement until valid Android builds are receiving tokens.
8. Enable Cloud Messaging only; do not enable unused Firebase products.

Do not commit service-account keys, App Check debug tokens, `.env` files, or downloaded private credentials.

## Billing and budget protection

Haka is designed for low-volume use that may stay inside Firebase no-cost allowances, but no documentation or configuration can guarantee a zero bill.

In Google Cloud Console, open **Billing → Budgets & alerts** and scope a monthly budget to each Haka project. A reasonable initial Development example for an INR billing account is:

```text
Monthly budget: ₹1,000
10% alert:       ₹100   low-usage warning
50% alert:       ₹500   expected development threshold
100% alert:    ₹1,000   unexpected-usage threshold
```

Adjust these amounts to the billing account and acceptable risk. Add all responsible email recipients. Budget alerts notify; they do **not** automatically cap or stop spending.

Monitor at least weekly during development:

- Realtime Database connections, storage, downloads, and writes;
- Cloud Functions invocations, errors, execution time, and outbound bandwidth;
- Cloud Messaging failures and invalid tokens;
- Cloud Billing reports grouped by project and service.

The backend avoids minimum instances, permanently stored tap events, high-frequency schedules, and a 30-minute decay job. Processed tap IDs are bounded to seven days and cleaned daily.

As of 2026-08-22, `npm audit --omit=dev` reports seven moderate transitive `uuid` advisories through current Firebase/Google Cloud dependencies. The suggested forced fix would downgrade `firebase-admin` across a breaking major version, so it has not been applied. Re-run the audit before deployment and adopt an upstream non-breaking fix when Firebase publishes one.

## Local setup

```bash
nvm use
cd functions
npm ci
npm run verify:node
npm test
cd ..
```

Start the full local stack:

```bash
./functions/node_modules/.bin/firebase emulators:start \
  --project demo-haka \
  --only auth,functions,database
```

Configured local ports:

```text
Auth       127.0.0.1:9199
Functions  127.0.0.1:5101
Database   127.0.0.1:9100
UI         127.0.0.1:4001
```

Run integration and Security Rules tests in a second terminal:

```bash
cd functions
npm run test:emulator
```

Or run everything in one command:

```bash
./functions/node_modules/.bin/firebase emulators:exec \
  --project demo-haka \
  --only auth,functions,database \
  "cd functions && npm run test:emulator"
```

The Firebase CLI sets `FUNCTIONS_EMULATOR=true`, which disables callable App Check enforcement only inside the Functions emulator. Remote staging and production Functions always enforce App Check.

## App Check

### Android development/debug builds

Use Firebase's Android App Check debug provider only in debug builds. Launch the debug build, obtain the generated debug token from logs, and register it in **Firebase Console → App Check → Apps → Manage debug tokens**.

Never:

- commit the debug token;
- put the debug provider in release builds;
- share a debug APK publicly;
- disable remote enforcement as a workaround for a broken release build.

Local Functions emulator calls do not require App Check. For Staging, register the staging app and debug token before enabling enforcement.

### Production

Use Play Integrity with the production package and release signing SHA-256 certificate. Verify valid App Check metrics first, then enable enforcement for Cloud Functions and Realtime Database. Roll out enforcement environment by environment.

## Authentication and recovery

Anonymous Auth is a first-launch identity, not a recovery mechanism. Before relying on Haka across devices, Android must link the anonymous user to Google or another durable provider using Firebase Auth credential linking.

Correct linking preserves the Firebase UID:

```text
anonymous UID → link Google credential → same UID → same coupleId
```

On a new device, sign in with the linked provider and call `getBootstrap`. The backend verifies membership and returns the existing heart, daily state, and streak. Device IDs and invite codes are never accepted as identity recovery.

Test provider-collision handling before launch: if a Google credential already belongs to another Firebase user, do not silently replace or merge couple membership.

## Functions contract

All callable Functions require Firebase Auth and remote App Check:

- `createCouple`
- `redeemInvite`
- `getBootstrap`
- `tapHeart`

`tapHeart` validates membership and a UUID `tapId`, applies rate limits, uses server time, materializes linear decay, adds 25 points, updates daily/streak state, and records the tap ID in the same authoritative transaction. Duplicate IDs return the existing authoritative result without incrementing totals.

The Android client must not submit timestamps, score, totals, streak values, or membership changes.

## Realtime Database Security Rules

`database.rules.json` denies access by default. Couple members can read only public heart/today/streak/history paths. Clients cannot read the processed-tap ledger or directly write authoritative state, membership, totals, or streaks.

Rules tests verify:

```text
User A → own couple public state     ALLOW
User B → same couple public state   ALLOW
User C → couple A                   DENY
Unauthenticated → couple A          DENY
Member → internal ledger            DENY
Member → authoritative mutation     DENY
```

Deploy rules only after emulator tests pass:

```bash
firebase deploy --only database --project dev
```

Do not loosen production rules for Android development.

## Storage, cleanup, history, and FCM

- The heart stores compact aggregate state, not permanent per-tap events.
- `state/internal/recentTapIds` provides seven-day replay protection.
- `cleanupExpiredData` runs once daily, expires pending invites, removes old invite records, and removes old tap IDs. Cleanup is maintenance; idempotency correctness does not depend on immediate cleanup.
- `daily/{yyyy-MM-dd}` is a deterministic projection of authoritative `today` state and is safe to overwrite on retries.
- Daily boundaries are calculated from `couple.timezone` and trusted server time.
- FCM device records contain token, preference, and update time. Partner-activity notifications are throttled to at most one per five minutes and notification failures cannot fail an accepted tap.

## Predeployment gate

Do not deploy until all items are true:

```bash
nvm use
cd functions
npm ci
npm run verify:deploy
cd ..

./functions/node_modules/.bin/firebase emulators:exec \
  --project demo-haka \
  --only auth,functions,database \
  "cd functions && npm run test:emulator"
```

Then verify manually:

- the selected Firebase alias and project ID;
- Blaze billing is attached to the intended project;
- budget alerts and recipients exist;
- Functions region is `asia-south1`;
- Node runtime is 22;
- Authentication providers are correct for that environment;
- App Check app registration and enforcement state are intentional;
- Realtime Database location and rules are correct;
- no local/emulator credentials or debug tokens are present.

## Deployment

Deploy Development first:

```bash
firebase use dev
firebase deploy --only database,functions
```

Promote the same reviewed commit to Staging and then Production:

```bash
firebase use staging
firebase deploy --only database,functions

firebase use prod
firebase deploy --only database,functions
```

The configured predeploy hook rejects non-Node-22 deployments and runs the build/unit suite. Emulator integration remains an explicit required step because deployment hooks should not start a second long-running local stack unexpectedly.

## Production smoke test

Use two dedicated test accounts and a disposable test couple:

1. A authenticates and creates a couple.
2. B redeems the one-time invite.
3. A taps once; B observes the public heart update.
4. A retries the same `tapId`; totals do not change.
5. B taps; daily completion and streak update.
6. A signs in again on a fresh session/device and `getBootstrap` returns the same UID, couple ID, heart, and streak.
7. A third account and unauthenticated request cannot read the couple.

Remove or intentionally retain the disposable test data after validation. Never use an invite code as recovery proof.

## Rollback

Keep deployments tied to reviewed Git commits.

For a Functions regression:

1. Select the correct environment alias.
2. Check out or revert to the last known-good commit in a separate clean worktree.
3. Run its tests and emulator suite.
4. Redeploy Functions from that commit: `firebase deploy --only functions`.

For a Rules regression, redeploy the last known-good `database.rules.json` with `firebase deploy --only database`. Rules rollback does not restore deleted or overwritten data.

Before schema migrations or destructive maintenance, export/backup Realtime Database through approved Firebase/Google Cloud tooling. Never change the Functions region as an emergency rollback.

## Current external prerequisites

The repository is deployment-ready, but remote hosting cannot be completed until the owner supplies or creates:

- Development, Staging, and Production Firebase project IDs;
- a Blaze-linked billing account;
- budget amounts and notification recipients;
- Android package IDs and signing SHA-256 fingerprints;
- enabled Authentication providers;
- Firebase CLI access authorized for those projects.

## Official operational references

- [Cloud Functions runtime and region management](https://firebase.google.com/docs/functions/manage-functions)
- [Firebase App Check with Play Integrity](https://firebase.google.com/docs/app-check/android/play-integrity-provider)
- [Firebase App Check Android debug provider](https://firebase.google.com/docs/app-check/android/debug-provider)
- [Firebase Security Rules emulator testing](https://firebase.google.com/docs/rules/unit-tests)
- [Google Cloud budgets and alerts](https://cloud.google.com/billing/docs/how-to/budgets)
