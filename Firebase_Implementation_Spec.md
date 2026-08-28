# Haka — Firebase Implementation Specification

This document fixes the first backend contract for the Android MVP.

## 1. Authoritative invariants

```text
MAX_SCORE = 10_000
DECAY_INTERVAL_SECONDS = 1_800
DECAY_AMOUNT = 500
TAP_AMOUNT = 25
```

The decay model is linear, never multiplicative:

```text
intervals = floor((serverNow - lastUpdatedAt) / 1_800)
effectiveScore = clamp(score - intervals * 500, 0, 10_000)
```

Every accepted tap adds 25 points after decay is materialized. A tap is accepted at most once by its `tapId`. The client never supplies score, counters, streak, date, or timestamps.

## 2. Realtime Database schema

Use a small public read model and a private command ledger. Cloud Functions use the Admin SDK, while Android receives live updates from the public couple state.

```text
users/{uid}
  displayName: string
  coupleId: string | null
  createdAt: number

couples/{coupleId}
  members/{uid}: "owner" | "partner"
  timezone: "Asia/Kolkata"
  status: "active" | "unpaired"
  createdAt: number

  state/
    heart/
      score: number
      maxScore: 10000
      totalTaps: number
      lastUpdatedAt: number
      lastTapAt: number | null

    today/
      date: "2026-08-21"
      tapsByUser/{uid}: number
      totalTaps: number
      completed: boolean
      completedAt: number | null

    streak/
      current: number
      longest: number
      lastCompletedDate: string | null

    internal/
      recentTapIds/{tapId}/
        uid: string
        acceptedAt: number
        expiresAt: number

  daily/{yyyy-MM-dd}/
    tapsByUser/{uid}: number
    totalTaps: number
    completed: boolean
    completedAt: number | null

  milestones/{milestoneId}/
    type: string
    value: number
    achievedAt: number

inviteCodes/{code}
  coupleId: string
  creatorUid: string
  expiresAt: number
  status: "pending" | "redeemed" | "expired"
  redeemedBy: string | null
  redeemedAt: number | null

devices/{uid}/{deviceId}
  fcmToken: string
  updatedAt: number
  notificationsEnabled: boolean
```

### Why `state` and `daily` are separate

`state` contains the values the Home screen needs and the compact data required for the authoritative tap transaction. `daily` is the history projection used by Stats and History. The function updates the current state first, then writes the daily projection with a retry-safe derived update; older history can be repaired or rebuilt from trusted command records if necessary.

Retain `internal/recentTapIds` for a bounded period such as 7 days, then remove expired IDs with a daily cleanup function. This prevents the idempotency ledger from growing forever while covering delayed retries.

## 3. Callable Functions

Use second-generation callable Cloud Functions in a single region close to the expected users. Callable functions automatically carry Firebase Auth and App Check tokens when available; reject missing or invalid App Check in production. See [Firebase callable functions](https://firebase.google.com/docs/functions/callable?hl=en).

### `createCouple`

Input: `{ displayName?: string, timezone: string }`

Server flow:

1. Require Auth and App Check.
2. Verify the caller has no active `coupleId`.
3. Validate an IANA timezone.
4. Create a random, non-guessable invite code with a 15-minute expiry.
5. Create the couple with one member and initial state.
6. Set `users/{uid}/coupleId` and return `{ coupleId, inviteCode, expiresAt }`.

### `redeemInvite`

Input: `{ code: string }`

Server flow:

1. Require Auth and App Check.
2. Normalize and validate the code.
3. Execute a transaction on the invite record so only one redemption wins.
4. Reject expired, redeemed, self, already-paired, or full-couple requests.
5. Add the second member and set both users' `coupleId` values in one multi-location update.
6. Return the couple ID and partner profile.

### `tapHeart`

Input:

```json
{
  "coupleId": "CPL_82F9A1",
  "tapId": "client-generated-uuid"
}
```

Server flow:

1. Require Auth and App Check.
2. Validate `tapId` format/length and verify the caller belongs to `coupleId`.
3. Enforce a per-user and per-couple rate limit. Return `resource-exhausted` when exceeded.
4. Run a transaction on `couples/{coupleId}/state`.
5. If `recentTapIds/{tapId}` exists, return the existing result without incrementing anything.
6. Derive the couple-local date from trusted server time and the couple timezone.
7. If the stored `today.date` differs, evaluate the prior day, advance/reset the streak, and create a fresh today state.
8. Materialize linear decay from `heart.lastUpdatedAt` using 500 points per completed 1,800-second interval.
9. Add 25 points, clamp to 10,000, increment total and daily counters, and set `lastUpdatedAt`/`lastTapAt` to server time.
10. Set `today.completed = tapsByUser[memberA] > 0 && tapsByUser[memberB] > 0`.
11. Record the `tapId` and accepted result in the bounded ledger.
12. Return the authoritative heart, today's counts, streak, and whether the request was newly accepted.

The transaction is the serialization point for concurrent taps. The function must not perform separate client writes to heart, daily, or streak paths. The current heart/today/streak state is authoritative; Stats history is a derived projection updated by the function from the accepted command result with a retry-safe write.

Example response:

```json
{
  "accepted": true,
  "duplicate": false,
  "score": 7425,
  "percentage": 74.25,
  "totalTaps": 1843,
  "today": { "myTaps": 125, "partnerTaps": 117, "completed": true },
  "streak": { "current": 19, "longest": 42 }
}
```

### `getBootstrap`

Input: `{}`

After any durable-provider sign-in, the client calls this function to restore its backend session. The function:

1. Requires Auth and App Check.
2. Reads `users/{uid}`.
3. Resolves `coupleId` and verifies the UID is still a member.
4. Returns the couple metadata and public heart/today/streak state.
5. Never accepts an invite code or replacement UID as recovery proof.

Anonymous-to-Google linking is performed through Firebase Authentication on the Android client. Correct linking preserves the Firebase UID, so no couple data migration is required.

## 4. Linear decay examples

```text
score = 10,000 at 10:00

10:29 → 10,000
10:30 →  9,500
11:00 →  9,000
12:00 →  8,000
15:00 →  5,000
20:00 →      0
```

If a tap arrives at 15:00 after a score of 8,000 at 10:00, the function first applies ten intervals of decay (`8,000 - 5,000 = 3,000`) and then adds 25, resulting in 3,025.

## 5. Realtime Database Security Rules starter

All authoritative writes go through Admin SDK functions. Admin SDK writes bypass Realtime Database Rules, so callable functions must perform their own validation. Client rules should primarily expose reads and limited profile/device preference writes.

```json
{
  "rules": {
    ".read": false,
    ".write": false,

    "users": {
      "$uid": {
        ".read": "auth != null && (auth.uid === $uid || (data.child('coupleId').exists() && root.child('users').child(auth.uid).child('coupleId').val() === data.child('coupleId').val()))",
        "displayName": {
          ".write": "auth != null && auth.uid === $uid",
          ".validate": "newData.isString() && newData.val().length >= 1 && newData.val().length <= 40"
        },
        "coupleId": { ".write": false },
        "createdAt": { ".write": false }
      }
    },

    "couples": {
      "$coupleId": {
        ".read": false,
        ".write": false,
        "state": {
          ".read": false,
          ".write": false,
          "heart": { ".read": "auth != null && root.child('couples').child($coupleId).child('members').child(auth.uid).exists()" },
          "today": { ".read": "auth != null && root.child('couples').child($coupleId).child('members').child(auth.uid).exists()" },
          "streak": { ".read": "auth != null && root.child('couples').child($coupleId).child('members').child(auth.uid).exists()" },
          "internal": { ".read": false, ".write": false }
        },
        "daily": {
          ".read": "auth != null && root.child('couples').child($coupleId).child('members').child(auth.uid).exists()",
          ".write": false
        },
        "milestones": {
          ".read": "auth != null && root.child('couples').child($coupleId).child('members').child(auth.uid).exists()",
          ".write": false
        },
        "internal": { ".read": false, ".write": false }
      }
    },

    "inviteCodes": { "$code": { ".read": false, ".write": false } },

    "devices": {
      "$uid": {
        ".read": "auth != null && auth.uid === $uid",
        "$deviceId": {
          ".write": "auth != null && auth.uid === $uid",
          ".validate": "newData.hasChildren(['fcmToken', 'updatedAt', 'notificationsEnabled']) && newData.child('fcmToken').isString() && newData.child('fcmToken').val().length <= 4096 && newData.child('updatedAt').isNumber() && newData.child('notificationsEnabled').isBoolean()"
        }
      }
    }
  }
}
```

The rules deliberately do not attempt to calculate the heart transaction. They ensure clients cannot write the authoritative nodes and restrict reads to members. Add `.indexOn` entries for any ordered History queries before launch. Firebase rules support `.read`, `.write`, `.validate`, and `.indexOn`; `.validate` can inspect the merged `newData` state. See [Realtime Database security](https://firebase.google.com/docs/database/security) and the [Rules API](https://firebase.google.com/docs/reference/security/database/).

## 6. Android client contract

```kotlin
interface HeartRepository {
    fun observeCoupleState(coupleId: String): Flow<CoupleState>
    suspend fun tapHeart(coupleId: String, tapId: String): TapResult
}
```

Client behavior:

- Generate `tapId = UUID.randomUUID().toString()` before submission.
- Save pending commands in Room.
- Animate locally, but mark the result as pending until the function accepts it.
- Retry the same `tapId`, never a new ID, after timeout.
- Treat a duplicate response as successful reconciliation, not as a second tap.
- Replace local state with the authoritative function/listener state after every accepted response.

## 7. Required emulator tests

### Pairing

- valid invite;
- expired invite;
- malformed code;
- same code redeemed twice concurrently;
- creator attempts self-pair;
- already-paired user;
- third user joins a full couple.

### Tap concurrency and idempotency

- A taps once;
- both partners tap simultaneously;
- rapid taps from both partners;
- same `tapId` submitted twice or retried after timeout;
- two different taps submitted concurrently;
- forged couple ID;
- missing/invalid App Check;
- per-user and per-couple rate limits.

### Decay

- zero elapsed time;
- 1,799 seconds: no decay;
- 1,800 seconds: exactly 500 points;
- 3,600 seconds: exactly 1,000 points;
- multi-hour and multi-day decay;
- score reaches zero and never becomes negative;
- tap after decay materialization;
- tap at the exact interval boundary.

### Streak and timezone

- first completed day;
- consecutive completed days;
- missed day reset;
- both members tap around midnight;
- couple timezone differs from device timezone;
- timezone change policy;
- daily state rollover with a simultaneous tap.

## 8. Deployment sequence

1. Create separate Firebase dev, staging, and production projects.
2. Add Realtime Database, Auth, Functions, FCM, App Check, Crashlytics, and Emulator Suite configuration.
3. Deploy rules and indexes before enabling the Android client.
4. Deploy callable functions with App Check enforcement in staging first.
5. Run emulator and two-device concurrency tests.
6. Enable production App Check enforcement only after valid release builds are registered.
7. Add cleanup for expired invite codes and old `recentTapIds`.
8. Monitor function errors, rejected taps, duplicate rate, latency, database operations, and cost during closed testing.

## 9. Official references

- [Callable Cloud Functions and App Check](https://firebase.google.com/docs/functions/callable?hl=en)
- [Realtime Database transactions and multi-location writes](https://firebase.google.com/docs/database/admin/save-data?hl=en)
- [Realtime Database Security Rules](https://firebase.google.com/docs/database/security)
