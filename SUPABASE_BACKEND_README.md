# Haka Supabase Backend

This is Haka's card-free online backend. It preserves the Firebase contract while moving the authoritative state machine to Supabase Free.

## Hosted project

- Supabase project ref: `qvkzcqsgisrdkbnuylcw`
- Organization: `Haka`
- Plan: Free
- Intended database region: South Asia (Mumbai), `ap-south-1`
- Android auth redirect: `haka://auth/callback`
- Deployment status: database, RLS, Auth config, Realtime, and all five Edge Functions are live
- Last production smoke test: passed on 2026-08-24; generated test data was removed

The Firebase implementation remains in `functions/` as a fallback. Do not deploy those Cloud Functions unless the Firebase project is upgraded to Blaze.

## Architecture

```text
Haka Android
  ├─ Supabase Auth (anonymous first, durable provider linking later)
  ├─ Authenticated Edge Functions
  │    ├─ create-couple
  │    ├─ redeem-invite
  │    ├─ get-bootstrap
  │    ├─ tap-heart
  │    └─ register-device
  ├─ PostgreSQL atomic RPC state machine
  ├─ Row-Level Security
  ├─ Realtime: heart_state, daily_stats, streaks
  └─ FCM HTTP v1 (optional service-account secret)
```

Clients cannot mutate couple membership, heart score, daily totals, streaks, invites, or processed tap IDs directly. Edge Functions authenticate the caller, then invoke service-role-only RPC functions. All public tables have RLS enabled.

## Product invariants

```text
heart score       0..10000
linear decay      -500 per completed 1800 seconds
accepted tap      +25
tap idempotency   7 days
invite lifetime   15 minutes, one use
user rate limit   20 accepted taps/second
couple rate limit 50 accepted taps/second
notification      max one partner-tap notification per 5 minutes
```

Decay is materialized lazily during `tap-heart` and `get-bootstrap`. Cleanup is also lazy during backend commands, avoiding a paid scheduler.

## Repository layout

- `supabase/migrations/`: schema, RLS, RPCs, Realtime publication
- `supabase/functions/`: authenticated Edge endpoints and FCM adapter
- `supabase/tests/`: transactional pgTAP domain/security suite
- `scripts/supabase-smoke.mjs`: live HTTP smoke test
- `supabase/config.toml`: local stack and remote Auth configuration

## Deployment

```bash
npm install
./node_modules/.bin/supabase login
./node_modules/.bin/supabase link --project-ref qvkzcqsgisrdkbnuylcw
./node_modules/.bin/supabase db push --linked --include-all
./node_modules/.bin/supabase config push --project-ref qvkzcqsgisrdkbnuylcw
./node_modules/.bin/supabase functions deploy \
  create-couple redeem-invite get-bootstrap tap-heart register-device \
  --project-ref qvkzcqsgisrdkbnuylcw --use-api
```

`--use-api` bundles functions remotely and does not require Docker.

## Verification

With Docker installed:

```bash
npm run supabase:start
npm run supabase:reset
npm run test:supabase
npm run supabase:lint
```

For a live smoke test, provide the project URL, publishable/anon key, and service-role key as temporary shell environment variables. The service key is used only to seed the one-hour decay case and remove test data. Never commit these values to `.env`:

```bash
SUPABASE_URL=https://qvkzcqsgisrdkbnuylcw.supabase.co \
SUPABASE_ANON_KEY=... \
SUPABASE_SERVICE_ROLE_KEY=... \
npm run smoke:supabase
```

The smoke test creates three anonymous test identities and one test couple. It verifies pairing, an accepted tap, duplicate idempotency, exact one-hour linear decay (`8000 → 7025` after a tap), daily completion, streak, bootstrap recovery, authorization, and forged input rejection. A `finally` cleanup removes smoke-test couples and identities.

## Android contract

Send the Supabase access token as `Authorization: Bearer <token>` and the project publishable/anon key as `apikey`. Invoke:

```text
POST /functions/v1/create-couple
POST /functions/v1/redeem-invite
POST /functions/v1/get-bootstrap
POST /functions/v1/tap-heart
POST /functions/v1/register-device
```

Subscribe to Postgres changes for the signed-in user's authorized `couple_id` on:

- `heart_state`
- `daily_stats`
- `streaks`

RLS filters all reads, but Android should still filter subscriptions by `couple_id` to minimize messages.

## FCM

FCM remains usable on the Firebase Spark project. To enable partner notifications, create a narrowly controlled Firebase service account with FCM send permission and store its JSON as a Supabase secret:

```bash
./node_modules/.bin/supabase secrets set \
  FIREBASE_SERVICE_ACCOUNT_JSON='...' \
  --project-ref qvkzcqsgisrdkbnuylcw
```

Never commit or paste the service-account JSON into source control. If the secret is absent, taps still succeed and notification delivery is skipped.

## Free-plan expectations

Supabase Free currently includes 500,000 Edge Function invocations, Realtime, and a dedicated Postgres project. Free projects have quotas and may be paused after inactivity; they do not provide a production uptime SLA. Review current limits before expanding beyond the initial couple.
