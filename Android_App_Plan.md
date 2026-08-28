# Haka — Android App Plan

## 1. Product definition

**Shared Heart** is a private two-person Android app where one couple owns one continuously shared heart. Either partner can tap the heart; both phones see the same state in real time. Taps raise the heart's energy, energy decays over time, and both partners maintain a streak by participating each day.

### MVP promise

> Open the app, see the current shared heart, tap it, and know your partner will see the change.

### MVP success criteria

- A new user can authenticate and create or join one couple.
- A partner can join with a short-lived invite code.
- Both phones receive heart changes in near real time.
- Taps are attributed to the correct partner and counted daily and all-time.
- Heart decay and streak rules are calculated consistently using server time.
- Users can recover gracefully from offline mode, force-closes, rotation, and device changes.

## 2. Recommended Android stack

- **Language:** Kotlin
- **UI:** Jetpack Compose, Material 3, adaptive layouts
- **Architecture:** single activity, Navigation Compose, ViewModels, repositories, Kotlin coroutines and `StateFlow`
- **Dependency injection:** Hilt
- **Backend:** Firebase Authentication, Realtime Database, Cloud Functions, App Check
- **Push:** Firebase Cloud Messaging
- **Local preferences/cache:** Room for last-known couple state and queued commands; DataStore for preferences
- **Widget:** Jetpack Glance
- **Background work:** WorkManager for sync/retry and widget refresh
- **Observability:** Firebase Crashlytics, Performance Monitoring, Analytics, and Remote Config
- **Testing:** JUnit, Kotlin coroutine test tools, Compose UI tests, Firebase Emulator Suite

This follows Android's current guidance to use a clear data layer, repositories, coroutines/flows, a single activity, and Compose. Glance is the Compose-based option for the home-screen widget. See the [Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations) and [Glance documentation](https://developer.android.com/develop/ui/compose/glance).

## 3. Product rules to finalize before implementation

Write these rules as backend invariants and automated test cases before implementation. Use these defaults for version 1 and make safe tuning parameters Remote Config values later.

### Heart

- Store energy as an integer score from `0` to `10,000`; display it as a percentage.
- Linear decay is **5 percentage points every 30 minutes**: `DECAY_INTERVAL = 1,800 seconds`, `DECAY_AMOUNT = 500`.
- Each accepted tap adds `25` score (`0.25%`). Twenty accepted taps recover one 30-minute decay interval.
- Energy decays lazily when the heart is read or mutated, using trusted server time. Do not run a scheduled function every 30 minutes.
- Effective score is `max(0, score - floor((serverNow - lastUpdatedAt) / 1,800) * 500)`, capped at `maxScore` after additions.
- Store `lastUpdatedAt`, not a client-provided timestamp. When a tap arrives, first materialize accumulated decay, then apply the tap.
- Reaching 10,000 is a milestone and does not stop further taps; excess energy is capped.

### Daily participation and streak

- A day uses the couple's configured timezone, initially UTC or a selected timezone stored on the couple.
- Both partners must make at least one accepted tap on a calendar day for the day to complete.
- A completed day increments `currentStreak`; a missed day resets it to zero.
- Store `longestStreak` permanently.
- Do not infer streak completion from the client clock or require the heart to reach 100% for daily completion in MVP.

### Couple lifecycle

- One account belongs to at most one active couple in MVP.
- Invite codes expire after 15 minutes and can be redeemed once.
- A user cannot pair with themselves or join a third member.
- Leave/unpair is a deliberate settings action with confirmation; preserve historical data according to the privacy policy.

## 4. User journeys and screens

### First launch

1. Splash/loading and Firebase initialization.
2. Welcome screen: short explanation and privacy link.
3. Continue anonymously for fastest onboarding, or sign in with Google/email as an upgrade path.
4. Choose **Create a couple** or **Join with code**.

### Pairing

- **Create Couple:** generate code, show copy/share action, show waiting state, allow cancel/regenerate.
- **Join Couple:** code entry with automatic formatting, validation, expiry/error states, success confirmation.
- Pairing completion routes both devices to the Home screen.

### Main app

- **Home:** large animated heart, energy percentage, last interaction, today's taps, streak, partner presence/status, and primary tap action.
- **Tap feedback:** haptic feedback, scale/pulse animation, floating heart particles, optimistic animation with rollback/error handling.
- **Stats:** today, all-time, partner split, completed days, current/longest streak, milestone history.
- **History:** daily energy/completion summary; keep this out of the initial MVP if schedule is tight.
- **Settings:** partner display name, timezone, notification preferences, theme, account upgrade, unpair/delete account, legal links.

### Empty and failure states

Design explicitly for: no partner yet, expired invite, no network, stale data, authentication failure, server rejection, notification permission denied, and account already paired.

## 5. Android app architecture

```text
MainActivity
  └── AppNavHost
      ├── AuthGraph
      ├── PairingGraph
      └── CoupleGraph
          ├── HomeScreen
          ├── StatsScreen
          ├── HistoryScreen
          └── SettingsScreen

Compose UI → ViewModel → Use cases → Repository → Firebase / DataStore
                                  └──────────────→ local cache
```

Suggested packages/modules:

```text
app/
  core/model/
  core/designsystem/
  core/network/
  core/notifications/
  data/auth/
  data/couple/
  data/heart/
  data/stats/
  data/settings/
  domain/
  feature/auth/
  feature/pairing/
  feature/home/
  feature/stats/
  feature/history/
  feature/settings/
  widget/
```

Expose immutable UI state from ViewModels. Screens send user intents such as `TapHeart`, `RedeemInvite`, or `Retry`; they do not call Firebase directly.

## 6. Firebase backend design

### Authentication

Start with anonymous Firebase Auth to reduce onboarding friction. Add account linking to Google and email/password before launch if users need recovery across devices. Do not rely on a device ID as identity.

Anonymous authentication is only a first-launch identity. Before production, users must be able to link that identity to Google or another durable provider without changing the Firebase UID. A reinstall or new device signs in with that provider, calls the backend bootstrap operation, and restores the existing `coupleId`, heart, daily state, and streak. Pairing invite codes must never be accepted as account-recovery credentials.

### Realtime Database schema

```text
users/{uid}
  displayName
  coupleId
  createdAt
  authProvider

inviteCodes/{code}
  creatorUid
  coupleId
  expiresAt
  status

couples/{coupleId}
  members/{uid}: "owner" | "partner"
  timezone
  createdAt
  status

  heart/
    score
    maxScore
    totalTaps
    lastUpdatedAt
    lastTapAt

  daily/{yyyy-MM-dd}/
    tapsByUser/{uid}: number
    totalTaps
    completed
    completedAt

  streak/
    current
    longest
    lastCompletedDate

  processedTaps/{tapId}
    uid
    acceptedAt
    scoreAdded

  settings/
    decayPercent
    decayIntervalSeconds

  milestones/{milestoneId}
    type
    achievedAt
    value
```

Keep aggregate state separate from optional tap events. Do not store every tap in MVP. If detailed history is later needed, add a bounded event stream or export pipeline rather than making the main heart listener process an ever-growing node.

### Tap command

The client submits a narrow command containing a client-generated UUID: `{ tapId }`. The trusted backend applies the complete update:

1. Verify App Check, authentication, and couple membership.
2. Reject the request if `tapId` has already been processed.
3. Enforce per-user and per-couple rate limits.
4. Read server time and lazily apply all elapsed 30-minute decay intervals.
5. Add `25` score, capped at `maxScore`.
6. Increment heart total taps, daily user taps, and daily total.
7. Recalculate daily completion and streak using the couple timezone.
8. Record `tapId` and write the related paths as one authoritative operation.
9. Emit a notification event only when notification preferences and throttling allow it.

Use a callable Cloud Function or equivalent trusted backend command for the production tap path so validation, idempotency, decay, counters, and streak updates have one authority. Realtime Database listeners remain the live read path. Use Realtime Database transactions/server-side increments inside the trusted operation where appropriate; do not expose raw counter writes to the Android client. See Firebase's [Android read/write guidance](https://firebase.google.com/docs/database/android/read-and-write) and [Realtime Database security rules](https://firebase.google.com/docs/database/security).

## 7. Security model

Security is a core feature because the app's meaning depends on trustworthy shared state.

- Require `auth != null` for all user data.
- Enforce Firebase App Check for callable functions and database access where supported. App Check is an abuse-reduction layer, not a replacement for Authentication or Security Rules.
- Allow reads only when the authenticated UID is a member of the requested couple.
- Never allow clients to write `users/{uid}/coupleId`, couple membership, streak totals, decay settings, or lifetime totals directly.
- Restrict invite creation to an authenticated, unpaired user.
- Redeem invites through a callable Cloud Function or tightly validated backend transaction.
- Validate numeric ranges, date formats, immutable fields, and maximum payload sizes in rules.
- Rate-limit taps per UID/couple to prevent scripted inflation; choose a generous human threshold and return a friendly error when exceeded.
- Give every accepted tap a unique `tapId`; duplicate delivery must be a no-op.
- Store only the minimum profile data needed: UID, display name, couple ID, timestamps, device notification token, and preferences.
- Provide account deletion and data deletion/export behavior before public launch.

Rules must be tested with the Firebase Emulator Suite, including cross-couple reads, forged counters, expired invites, replayed codes, duplicate tap IDs, offline replay, rate limits, and unauthorized membership changes.

### Non-negotiable backend invariants

1. A couple has exactly two active members.
2. A user belongs to at most one active couple.
3. Only couple members can read that couple's state.
4. Clients cannot directly mutate authoritative heart, streak, membership, or lifetime totals.
5. Every accepted tap has a unique `tapId` and is counted at most once.
6. A tap cannot raise the score above `maxScore`.
7. Daily boundaries use the couple timezone.
8. Decay uses trusted server time and is linear: 500 points per completed 30-minute interval.

## 8. Offline and synchronization strategy

- Show the last known heart immediately from the Room-backed local state.
- Render connection state subtly: synced, syncing, offline, or needs attention.
- Queue tap commands locally with their `tapId` so retries do not double-count.
- Do not allow unlimited offline accumulation. Cap queued commands and/or require reconnection after a reasonable threshold; the backend rate limit remains authoritative.
- Treat local tap animations as presentation feedback, not accepted taps. Reconcile with the server response after reconnect.
- Reconcile server state after reconnect and after app process recreation.
- Use WorkManager for deferred retry and widget refresh, not as a substitute for real-time listeners.

## 9. Notifications and widget

### FCM

Use FCM for:

- partner tapped after a quiet period;
- heart energy below a threshold;
- streak reminder;
- milestone reached.

Respect notification permission on Android 13+, quiet hours, per-event settings, and server-side throttling. Foreground and background message behavior differs, so notification deep links must be tested in both states. For longer background work, schedule WorkManager rather than doing it inside `onMessageReceived`; see [FCM message handling](https://firebase.google.com/docs/cloud-messaging/android/receive-messages).

### Glance widget

Create one small widget for the MVP:

```text
OUR HEART
73%  ███████░░
🔥 18 day streak
You 124 • Partner 87
```

Store a compact last-known snapshot in Room. Update immediately when the app is active or handles a relevant FCM event, and periodically through the widget/WorkManager mechanisms. Do not refresh every tap or every minute; widgets are system-managed and frequent background updates cost battery. See [Glance widget update guidance](https://developer.android.com/develop/ui/compose/glance/glance-app-widget).

## 10. Visual and interaction direction

- Warm, intimate, calm visual language rather than a competitive dashboard.
- Heart is the dominant element; statistics remain secondary.
- Use Material 3 semantics and content descriptions, with color not being the only status signal.
- Support dynamic color, dark theme, large fonts, TalkBack, reduced motion, and touch targets of at least 48dp.
- Make the tap interaction satisfying but short: pulse, haptic, sound optional, and no animation that blocks repeated taps.
- Use responsive layouts so the same code can support small phones, tablets, and foldables.

## 11. Delivery phases

### Phase 0 — Product and technical foundation

- Write backend invariants and test cases for heart, exact linear decay, tap value, idempotency, streak, timezone, pairing, and privacy.
- Freeze the Firebase schema, Security Rules, tap command contract, and App Check setup.
- Create Firebase dev/staging/prod projects.
- Create Android project, package name, signing setup, CI, lint, formatting, and baseline Compose theme.
- Add analytics event taxonomy and crash reporting.

**Exit:** clean app launches, environments are separated, emulator tests can run, and the foundation artifacts are reviewed.

### Phase 1 — Authentication and pairing

- Anonymous auth and user profile.
- Create/join couple flow.
- Invite code expiry and one-time redemption.
- Pairing security rules and emulator tests.

**Exit:** two emulator/device sessions can pair, restart, and recover their couple.

### Phase 2 — Shared heart loop

- Realtime heart listener.
- Server-authoritative tap command.
- UUID `tapId` generation, duplicate protection, rate limiting, and bounded offline queue.
- Concurrent tapping and optimistic UI.
- Offline/reconnect reconciliation.

**Exit:** two physical Android devices show consistent counters during rapid concurrent tapping.

### Phase 3 — Stats, decay, and streak

- Daily aggregates and partner attribution.
- Exact 30-minute/5-point lazy decay using server time.
- Daily completion and current/longest streak.
- Timezone and date-boundary tests.

**Exit:** deterministic backend tests cover midnight, missed days, clock tampering, and simultaneous taps.

### Phase 4 — Widget and notifications

- Glance widget and deep links.
- FCM token registration and notification preferences.
- Heart-low, streak, and milestone triggers with throttling.

**Exit:** widget remains useful after force-close; notifications work in foreground/background and open the correct screen.

### Phase 5 — Hardening and launch

- Accessibility audit, tablet/foldable checks, battery/network testing.
- Crash and performance dashboards.
- Privacy policy, account deletion, data retention, support email, store listing, screenshots.
- Closed test, staged rollout, and rollback plan.

## 12. Testing plan

### Unit tests

- decay calculation and score cap/floor;
- timezone/date key calculation;
- streak transitions;
- invite validation;
- tap idempotency and throttling;
- tap value, score cap, decay interval boundaries, and trusted-time behavior;
- ViewModel state transitions.

### Integration tests

- Authenticated user can read only their couple;
- pair creation and one-time invite redemption;
- atomic tap updates all aggregates;
- two concurrent taps do not lose increments;
- duplicate `tapId` delivery counts once;
- offline replay is bounded and reconciles correctly;
- offline queue reconciles correctly;
- Cloud Functions reject forged input.

### UI tests

- onboarding and pairing;
- tap feedback and error rollback;
- loading/offline/empty states;
- navigation deep links from widget and notification;
- dark mode, large font, TalkBack labels.

### Device matrix

Test at minimum on a small Android phone, current Pixel-class device, one Samsung device, Android 13, Android 14, and the current release. Add tablet/foldable validation before claiming adaptive support.

## 13. Analytics and operational metrics

Track privacy-safe product events such as `pairing_completed`, `heart_tapped`, `daily_completed`, `streak_extended`, `widget_added`, `notification_opened`, and `tap_rejected`. Avoid storing message content or unnecessary relationship data.

Monitor:

- pairing completion rate;
- first-day and seventh-day retention;
- daily active couples;
- heart taps per active couple;
- notification opt-in/open rate;
- tap rejection and sync failure rate;
- crash-free users and function error rate;
- Realtime Database read/write volume and cost.

## 14. Scope control

Do not include in the first release: chat, public profiles, social discovery, multiple partners, photo sharing, a full custom backend, elaborate rewards, or a detailed per-tap timeline. These all increase privacy, moderation, or reliability costs without improving the core shared-heart loop.

## 15. Recommended build order

Build the smallest vertical slice first:

```text
Anonymous auth
  → create/join couple
  → observe shared heart
  → tap from two devices
  → attribute daily taps
  → calculate decay/streak
  → add widget/notifications
```

The main architectural decision is to treat the couple as the owner of one heart. Android is only a client of that shared state; it should never be allowed to invent membership, streaks, totals, or decay results.
