# Haka ❤️

Haka is a private Android app for two people who want to stay emotionally connected throughout the day.

Each couple shares one living heart. Either partner can tap it, both devices see the authoritative state in real time, and the heart gradually loses energy unless the couple keeps participating together.

The app is designed around a simple promise:

> Open Haka, see your shared heart, send a little love, and know your partner can feel it.

## Highlights

- Shared heart with server-authoritative state
- Real-time partner taps and heart updates
- Linear heart decay: 1% every 30 seconds in the current MVP build
- Tap feedback with haptics, pulses, floating hearts, and full-heart celebration
- Couple creation and one-time invite-code pairing
- Google sign-in support for account recovery across devices
- Thinking of You actions from Home and Love
- Private Love Notes with push notifications
- Daily Mood sharing between partners
- Automatic Android notification-channel setup and foreground notification support
- Home-screen widget built with Jetpack Glance
- Offline tap queue with retry when connectivity returns
- Responsive Jetpack Compose UI for narrow Android devices
- Supabase Auth, PostgreSQL, Edge Functions, RLS, Realtime, and FCM delivery

## Product model

Haka is intentionally small and private. A user belongs to one active couple in the MVP, and a couple has exactly two members.

The backend owns all values that affect trust and shared state:

- heart score and decay
- tap totals and attribution
- daily completion
- current and longest streak
- couple membership
- invite-code validity
- idempotency and rate limiting
- Love Notes and Daily Mood data

The Android client renders state and sends commands. It never decides the authoritative score, timestamps, streak, membership, or partner identity.

## Current navigation

```text
Heart       Shared heart, tapping, Thinking of You, partner activity
Insights    Combined statistics and daily history
Love        Thinking of You, Love Notes, and Daily Mood
Settings    Account recovery, notifications, privacy, and sign out
```

## Architecture

```text
Android app
  ├── Jetpack Compose UI
  ├── ViewModels and StateFlow
  ├── Repository/data layer
  ├── Room cache and offline tap queue
  ├── Firebase Cloud Messaging service
  └── Jetpack Glance widget
          │
          ├── Supabase Auth
          ├── Authenticated Edge Functions
          ├── PostgreSQL RPC state machine
          ├── Row-Level Security
          ├── Supabase Realtime
          └── FCM HTTP v1 notification delivery
```

### Android stack

- Kotlin
- Jetpack Compose and Material 3
- Hilt dependency injection
- Coroutines and `StateFlow`
- Room for local state and queued taps
- WorkManager for retry work
- Jetpack Glance for the widget
- Firebase Cloud Messaging for partner notifications
- Supabase Kotlin SDK for Auth, Functions, PostgREST, and Realtime

### Backend stack

- Supabase PostgreSQL
- Supabase Auth with anonymous onboarding and Google identity linking
- Supabase Edge Functions with JWT verification
- PostgreSQL security-definer RPC functions
- Row-Level Security on public tables
- Private schema for idempotency, notification, Love Note, and Mood data
- FCM HTTP v1 using a server-only Firebase Admin credential

## Repository layout

```text
.
├── app/
│   └── src/main/java/com/haka/app/
│       ├── core/                 # Theme, models, networking, notifications
│       ├── data/                 # Repository, Room, settings
│       ├── feature/auth/         # Sign-in screen
│       ├── feature/home/         # Shared heart and tap interactions
│       ├── feature/insights/     # Stats and history
│       ├── feature/love/         # Love Notes and Daily Mood
│       ├── feature/pairing/      # Couple creation and invite redemption
│       ├── feature/settings/     # Account, notifications, privacy
│       ├── widget/               # Glance widget
│       └── work/                 # Offline tap retry
├── supabase/
│   ├── functions/                # Authenticated Edge Functions
│   ├── migrations/               # PostgreSQL schema, RPCs, RLS, Realtime
│   └── tests/                    # Database tests
├── functions/                    # Firebase backend fallback and emulator suite
├── scripts/                      # Smoke tests and project utilities
├── .github/workflows/            # CI configuration
├── Android_App_Plan.md           # Product and Android plan
├── BACKEND_README.md             # Firebase backend reference
├── Firebase_Implementation_Spec.md
└── SUPABASE_BACKEND_README.md    # Supabase deployment reference
```

## Requirements

- Android Studio with Android SDK 35
- JDK 17 for the Android build
- Node.js 22 for backend tooling
- Supabase CLI
- A Supabase project
- A Firebase project with an Android app registered as `com.haka.app`
- A Firebase service-account credential with FCM send permission for push notifications

The app supports Android 8.0/API 26 and newer. Android 12/API 31 is supported.

## Local Android setup

1. Clone the repository.
2. Add the local Supabase values to `local.properties`:

```properties
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
```

Use only a publishable/anon key in the Android app. Never use a Supabase service-role key in Android.

3. Download the Firebase Android client configuration from Firebase Console and place it at:

```text
app/google-services.json
```

This file is intentionally ignored by Git because it belongs to a specific Firebase project/environment.

4. Build the debug APK:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./gradlew :app:assembleDebug --no-daemon
```

The APK is written to:

```text
app/build/outputs/apk/debug/app-debug.apk
```

## Supabase setup and deployment

Install the project tools and link the intended Supabase project:

```bash
npm install
./node_modules/.bin/supabase login
./node_modules/.bin/supabase link --project-ref YOUR_PROJECT_REF
```

Apply the schema and deploy the Edge Functions:

```bash
./node_modules/.bin/supabase db push --linked --include-all

./node_modules/.bin/supabase functions deploy \
  create-couple redeem-invite get-bootstrap tap-heart register-device \
  thinking-of-you send-love-note get-love-notes set-mood get-mood \
  --project-ref YOUR_PROJECT_REF --use-api
```

The deployed functions require a valid Supabase Auth access token. JWT verification is enabled in `supabase/config.toml`.

### Configure FCM push delivery

Store the Firebase Admin service-account JSON as a Supabase secret. Do not commit the JSON or put it in Android resources:

```bash
./node_modules/.bin/supabase secrets set \
  FIREBASE_SERVICE_ACCOUNT_JSON='YOUR_SERVICE_ACCOUNT_JSON' \
  --project-ref YOUR_PROJECT_REF
```

The secret is used only by server-side Edge Functions. The Android app receives the Firebase client configuration, not the Admin credential.

Push events currently include:

```text
partner_tap
thinking_of_you
love_note
```

When the app is foregrounded, `HakaMessagingService` creates a local notification. When it is backgrounded, FCM displays the notification through the configured Android channel.

## Backend functions

| Function | Purpose |
| --- | --- |
| `create-couple` | Creates a couple, initializes the heart, and issues an invite code |
| `redeem-invite` | Validates and consumes a one-time invite |
| `get-bootstrap` | Returns the authenticated user, couple, heart, daily state, streak, and history |
| `tap-heart` | Applies decay, accepts an idempotent tap, updates totals, and optionally notifies the partner |
| `register-device` | Stores an authenticated device FCM token and notification preference |
| `thinking-of-you` | Records a rate-limited private nudge and sends a push notification |
| `send-love-note` | Stores a private 160-character note and sends a push notification |
| `get-love-notes` | Returns the couple's latest private notes |
| `set-mood` | Stores the authenticated user's mood for the couple's local day |
| `get-mood` | Returns both partners' mood values for the current couple day |

## Data and security

The PostgreSQL state machine validates membership and uses server time. Sensitive feature tables are in the `private` schema and are accessed through service-role-only RPC functions invoked by authenticated Edge Functions.

Important protections include:

- RLS enabled on public data tables
- No direct client writes to authoritative heart, couple, streak, or daily state
- Membership checks inside database functions
- One-time, expiring invite codes
- UUID validation for command IDs
- Idempotent tap processing
- Rate limits for taps, Thinking of You, and Love Notes
- No service-role key in the APK
- No Firebase service-account JSON in source control
- Android notification preference stored per authenticated device
- FCM delivery failures do not roll back an accepted heart or note event

## Heart rules

The heart uses integer score units from `0` to `10,000`.

```text
Maximum score: 10,000
Accepted tap:  +25 points
Decay:         -100 points every completed 30 seconds
```

That is a linear decay of 1 percentage point per 30 seconds. A tap adds
0.25 percentage points and does not reset the decay boundary. All arithmetic
is integer-based and the score is clamped to `0..10,000`.

Decay is calculated lazily from the last authoritative update. The client may visually materialize decay between network updates, but the backend remains the source of truth when a command is accepted.

## Testing

### Android build

```bash
./gradlew :app:assembleDebug --no-daemon
```

### Supabase database tests

With Docker available:

```bash
npm run supabase:start
npm run supabase:reset
npm run test:supabase
npm run supabase:lint
```

### Live smoke test

Use temporary environment variables only. Never commit them:

```bash
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
SUPABASE_ANON_KEY=YOUR_ANON_KEY \
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY \
npm run smoke:supabase
```

The smoke test should cover:

- anonymous user creation
- couple creation and invite redemption
- authorized and unauthorized access
- accepted tap and duplicate tap idempotency
- exact decay behavior
- daily completion and streak updates
- Love Note creation and retrieval
- Daily Mood creation and partner retrieval
- cleanup of generated test data

### Manual two-device test

1. Install the same debug build on two phones.
2. Sign in on both phones.
3. Create a couple on phone A and redeem the invite on phone B.
4. Open the app once on both phones to register FCM tokens.
5. Tap the heart on either phone and confirm both hearts update.
6. Send **Thinking of You** and confirm the partner notification panel entry.
7. Send a Love Note and confirm the partner notification and Love tab entry.
8. Select a Daily Mood and confirm the partner sees it in Love within the refresh interval.
9. Force-close and reopen both apps to confirm state recovery.

## Account recovery

Anonymous Auth keeps first launch frictionless, but anonymous identity alone is not enough for a device change. Users should link Google before relying on Haka across phones.

```text
Anonymous identity
        ↓
Link Google
        ↓
Same Supabase user identity
        ↓
Existing couple, heart, notes, moods, and streak
```

Invite codes are for pairing only. They are not account-recovery credentials.

## Release checklist

- Confirm the correct Supabase project and Firebase project are selected.
- Confirm Android `google-services.json` matches `com.haka.app`.
- Confirm service-account JSON is stored only as a Supabase secret.
- Test Google recovery on a second device.
- Test notifications with the partner app foregrounded, backgrounded, and force-closed.
- Test Poco X3 / Android 12 and other narrow-screen devices.
- Review Supabase Edge Function logs and FCM failures.
- Build a signed release AAB, not the debug APK.
- Verify the version code and version name before publishing.
- Configure crash reporting, budget alerts, and data deletion procedures.

## Version

Current Android release line: **2.0.0**

## Privacy direction

Haka is intended to keep relationship data private to the couple. Avoid adding public profiles, advertising identifiers, third-party analytics with message content, or permanent per-tap history without revisiting the privacy model and security rules.

## License

No open-source license has been selected yet. Until a license is added, all rights are reserved by the project owner.
