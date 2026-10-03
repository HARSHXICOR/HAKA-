# Haka for iOS

Native SwiftUI companion to the Android Haka app. It uses the same Supabase authentication, couples, heart, taps, decay, streaks, Love Notes, moods, memories, bucket lists, relationship dates, and Edge Functions.

## What works without an Apple Developer membership

- Build and run the complete app in the iOS Simulator.
- Use anonymous or Google authentication and the existing Supabase backend.
- Pair two simulator/app sessions and watch heart updates.
- Use all five tabs: Heart, Insights, Love, Us, and Settings.
- Add the Haka home-screen widget in Simulator.
- Exercise notification presentation with `xcrun simctl push`.
- Run unit tests and inspect layouts on multiple simulated iPhone sizes.

An Apple Developer membership is only required later for installing on a physical iPhone, APNs production delivery, TestFlight, and App Store distribution. Simulator push payloads verify the iOS notification UI but do not prove the production FCM/APNs route.

## Configure

1. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`.
2. Set the same Supabase project URL and publishable/anon key used by Android. This file is ignored by Git.
3. In Supabase Google provider settings, keep `haka://auth/callback` as an allowed redirect URL.

## Generate and run

```bash
cd ios
xcodegen generate
open HakaIOS.xcodeproj
```

Select the **Haka** scheme and an iPhone Simulator, then press Run.

## Test notification presentation in Simulator

With the app installed on a booted simulator:

```bash
xcrun simctl push booted com.haka.app.ios PushPayloads/thinking-of-you.apns
xcrun simctl push booted com.haka.app.ios PushPayloads/love-note.apns
```

## Real-time behavior

The app refreshes authoritative Supabase state every two seconds while open and calculates the 1%/30-second linear decay locally every second from the server timestamp. Taps still go through the existing authoritative Edge Function; a tap never resets the decay schedule on the client.
