# Architecture

How Orbi is put together: the code's layout, the decisions that shape it, and
how data, sync and links work. For what each feature does, see
[FEATURES.md](FEATURES.md).

- [Technologies](#technologies)
- [Project layout](#project-layout)
- [Key decisions](#key-decisions)
- [iCloud sync](#icloud-sync)
- [Links](#links)
- [Sign in with Apple](#sign-in-with-apple)

## Technologies

| Area | What Orbi uses |
| --- | --- |
| Language and UI | Swift 6 (strict concurrency), SwiftUI, Observation (`@Observable`) |
| Drawing and motion | SwiftUI `Canvas` + `TimelineView` (the universe, stars, worlds, galaxies), bitmap sprite cache (`SkySprites`), Core Motion (gyro parallax), RealityKit (the Focus together galaxy on iOS 18+) |
| Data | SwiftData with a versioned schema; two stores (synced and device-only) |
| Sync and sharing | CloudKit: private database for iCloud sync, public database for Focus together rooms |
| Charts | Swift Charts (Insights) |
| Sound and haptics | AVAudioEngine with procedural synthesis (`SoundSynth`, `AmbientSynth`), Core Haptics |
| System surfaces | WidgetKit (Home/Lock Screen/StandBy widgets, Control Center control), ActivityKit (Live Activity, Dynamic Island), App Intents (Siri, Shortcuts, Focus filter) |
| Distraction shield | FamilyControls, ManagedSettings, DeviceActivity (three extensions) |
| Notifications and alarms | UserNotifications (local only, with deep links), AlarmKit (day-plan alarms on iOS 26.1+) |
| Apple Watch | watchOS app over WatchConnectivity |
| Accounts | Sign in with Apple (AuthenticationServices), optional |
| Purchases | RevenueCat (Swift Package `purchases-ios-spm`), StoreKit underneath |
| Analytics | Firebase Analytics without ad ID (`FirebaseAnalyticsCore`), behind `Telemetry` |
| Links | Custom scheme `lumora://` and universal links on `www.mobapptech.com/lumora/` |
| Tests | Swift Testing (unit and integration), XCTest (UI) |
| Localization | String Catalogs, 13 languages (en + 12) |

## Project layout

```
Lumora/
  App/            Entry point, AppModel (the composition root, with its Plan and
                  Habits extensions), AppRuntime (the process-wide AppModel),
                  RootView, the tab shell, TimerEffectsCoordinator,
                  LaunchOptions, DemoDataSeeder
  Intents/        App Intents: Start / Start Timed focus, App Shortcuts,
                  the Focus filter, and the runner every intent goes through
  Core/           Design system (LMColor, LMFont, LMSpring/LMCurve, spacing),
                  components (CosmicButton, GlassCard, OrbitBar, chips, orbs,
                  StatisticsCardView, ShareCardView), utilities (SeededRandom, DateProvider)
  Models/         SwiftData models + versioned schema/migration plan
  Services/
    Timer/        FocusTimerEngine (pure state machine), FocusSessionController
    Rewards/      ProgressionEngine, UniverseLayout, RewardRules, RewardService,
                  RhythmCalculator, ProgressStats, AchievementCatalog, YearReview
    Odyssey/      OdysseyService, OdysseyRules, world and galaxy generators
    Together/     TogetherService over a CloudKit (or in-memory demo) backend
    Tasks/        TaskPlanner (pure sections + ordering), TaskStore (task writes)
    Plan/         DayPlanner (pure editing rules), PlanAlarmService (AlarmKit)
    Habits/       HabitStore (check-ins, focus credit, reminders)
    Persistence/  DataStore, CloudSync, TimerStateStore (SwiftData checkpoint)
    Feedback/     HapticsService (Core Haptics), AudioService + SoundSynth +
                  AmbientSynth (procedural audio), PellGuide (the companion's notes)
    Store/        PlusStore (RevenueCat), PlusFeature
    Analytics/    Telemetry (Firebase) and TelemetryEvent, the event catalog
    System/       Notifications, Live Activities, widget and watch sync,
                  Screen Time shield, Sign in with Apple, gyro parallax
  Features/       Onboarding, Home (Today), Plan, Tasks, Habits, Focus, Break,
                  Universe, Odyssey, Achievements (the Collection), Insights,
                  Together, Plus (paywall), Settings
  Animations/     CelestialPainter (stars, planets, moons), StarField,
                  CosmicBackground and SkyTheme, Odyssey painters,
                  celebration timeline/renderer/sequence
  Resources/      Asset catalog, String Catalogs, privacy manifest
Shared/           Code compiled into the app and its extensions: DeepLink,
                  PlusAccess, the app group, widget snapshot, Live Activity
                  attributes and intents, the day plan timeline, habit
                  schedules, palette, FocusCategory, StarShape
LumoraWidgets/    Widgets, the Control Center control and the Live Activity
                  (Lock Screen and Dynamic Island)
LumoraWatch/      The Apple Watch app
LumoraShieldMonitor/, LumoraShieldConfiguration/, LumoraShieldAction/
                  Screen Time extensions: schedule, shield look, shield buttons
LumoraTests/      Swift Testing unit and integration tests
LumoraUITests/    XCTest UI flows (and the App Store capture harness)
Config/           Info.plists, entitlements and build settings
Tools/            Scripts that render the app icon, launch image and IAP images
Marketing/        Scripts behind the App Store screenshots and video captures
```

The app follows one direction: views read an `@Observable` `AppModel`, which owns the
services; services own their SwiftData writes; pure engines (timer, progression, layout,
planner, insights) have no state of their own and are what most tests exercise.

## Key decisions

- **The timer is time-derived, not tick-driven.** `TimerSegment` stores start,
  accumulated pause and pause start. Remaining time is always computed from
  dates. `FocusTimerEngine` is a pure reducer: (state, action, now) → (state, events).
  Every action first *reconciles* with `now`, so:
  - a session that finishes while the app is suspended completes at its real deadline;
  - a pause that arrives after the deadline completes the session instead;
  - a pause longer than 10 minutes auto-ends the session, and the star is kept.

  The controller schedules a single wake-up at the deadline as a convenience
  only. Foreground and launch reconcile produce the same result without it.
- **The checkpoint is crash-safe and rewards are exactly-once.** Order per
  action: reduce → persist reward (idempotent, keyed by the segment UUID) →
  checkpoint state → side effects. If the app dies between the reward and the
  checkpoint, the next launch re-derives the same completion and
  `RewardService` dedupes it. This is covered by a test.
- **App Intents drive the same timer as the UI.** Siri, Spotlight, Shortcuts,
  the Action Button and the Live Activity's buttons reach the one `AppModel`
  in the process through `AppRuntime` (the intent may be the thing that
  launched the app, in the background). `FocusIntentRunner` reconnects to the
  existing Live Activity, reconciles with the clock, then calls the same
  `FocusSessionController` methods as the in-app buttons, so every change
  still goes through `send` and rewards stay exactly-once. See
  [Siri, Shortcuts and Focus filters](FEATURES.md#siri-shortcuts-and-focus-filters).
- **The universe is deterministic.** `ProgressionEngine` is pure: (session,
  history, existing objects) → drafts. Positions come from `SeededRandom`
  (SplitMix64) seeded with stable hashes of IDs and day keys, plus a
  deterministic overlap-avoidance search. Objects are stored and append-only,
  and each records its `sourceSessionID` and a unique `rewardKey`. Tests
  confirm that replaying history reproduces the stored universe exactly and
  that stars never overlap.
- **Day keys are stamped at completion** in the time zone of that moment, so
  history never shifts after travel or a time-zone change. A session that
  crosses midnight belongs to the day it ends.
- **The celebration runs on one clock.** All 10 beats are time ranges drawn by
  a pure renderer (`CelebrationRenderer.draw(t:)`), and haptics and sound
  start on the same instant. The sequence is skippable after 1.5 s. The
  reward is persisted before the sequence exists, so interruptions can't
  corrupt anything. Variants: standard 5.6 s, ended-early (60% scale),
  milestone 8.4 s (planet birth), Reduce Motion 1.2 s, and too-short (no star).
- **Visuals and sound are fully procedural.** Stars, planets, moons, nebulae
  and comets are vector shapes and gradients drawn by `CelestialPainter`.
  Sound cues (D-major bloom chord, chime, whoosh, singing bowl) and the
  ambient beds (deep-space hum, rain, tides, brown noise) are synthesized in
  code, so no asset files are needed.
- **Rendering is budgeted.** Animated canvases run only while visible and
  active, at 24–30 fps for ambient scenes and 60 fps during gestures and
  flights. The universe canvas culls objects outside the viewport and drops
  to a cheap level of detail below 0.45× zoom. Particles are capped at 240
  (120 on constrained devices and in "Calm" motion, 0 with Reduce Motion).
- **Parallax is gyro + touch.** Background stars form three depth layers
  (0.2 / 0.5 / 1.0) that follow both the camera pan and the device tilt;
  nebula washes and universe objects shift more gently, and the focus core
  stays still. `MotionParallaxService` reads Core Motion gravity at 30 Hz,
  low-passes it, re-centers on the holding angle over a few seconds, caps
  travel at ±16 pt, and follows with the Drift spring (0.90 / 1.00). The
  sensor runs only while a parallax view is on screen, the app is active and
  motion is "Full"; Reduce Motion, "Minimal", "Calm" and Low Power keep depth
  static. Views read the tilt once per frame inside their `TimelineView`, so
  sensor updates never re-run view bodies, and the timer never reads it.
- **The schema is CloudKit-compatible.** Every property has a default and
  relationships are optional. There are no unique constraints (uniqueness is
  enforced in `RewardService`). See [iCloud sync](#icloud-sync) for which store mirrors.

## iCloud sync

A new phone, or an iPad, shows the same sky.

- **Two stores in one container** (`DataStore.makeContainer`):
  - *Synced* (`default.store`, the original file): sessions, tasks, preferences,
    achievements, the Odyssey and `SharedFocus`. With sync on it mirrors to the person's
    private CloudKit database (`iCloud.com.mobapptech.lumora`).
  - *Device* (`device.store`): the sky (`CelestialObject`, `UniverseProgress`) and the
    running timer (`TimerCheckpoint`). Never synced.
- **The sky is redrawn, not synced.** `RewardService.rebuildUniverseIfNeeded` compares the
  stars with the qualifying sessions and, if they differ (a new device, or sessions that
  arrived from another one), replays the whole history with `ProgressionEngine.replay`.
  The same sessions always give the same sky. Day 1 of the universe is synced on
  `UserPreferences.universeCreatedAt` (schema 1.4.0).
- **Upgrading from 1.3** copies this device's sky and timer out of the old single store
  once, exactly as drawn, so nobody's sky moves on update.
- **Two devices that started separately** can each bring a preferences row, a ship profile,
  a world with the same ordinal, a duplicated ledger entry or achievement.
  `DataStore.mergeDuplicates` folds them into one, keeping the furthest along, on launch and
  after every import (`CloudSync` listens for remote changes and waits two seconds).
- **Settings › iCloud** turns it off or on; it takes effect on the next launch. UI tests and
  in-memory stores never sync. Erasing all data also erases it from iCloud.

## Links

`DeepLink` (in `Shared/`, so the widgets use it too) is the one place links are read and
built. Every link has two forms:

- `lumora://universe`: used by widgets and notifications;
- `https://www.mobapptech.com/lumora/universe/`: the shareable form. Messaging apps make it
  tappable. With Orbi installed it opens the app (universal link, associated domain
  `applinks:www.mobapptech.com`); otherwise a small page explains and offers "Open in Orbi".

| Path | Opens |
| --- | --- |
| `today`, `universe`, `odyssey`, `insights` | that tab |
| `collection` | the Collection, over Insights |
| `insights/year` | Year in review (Insights when there's nothing to tell yet) |
| `settings` | Settings |
| `tasks` | the Tasks sheet, over Plan |
| `plan` (also `orbit`) | Today's orbit, over Plan |
| `habits` | the Habits sheet, over Plan |
| `plus` | the Orbi+ paywall (nothing once Orbi+ is active) |
| `focus?minutes=50&category=reading` | the setup screen with those filled in (both optional, minutes clamped to 1–180) |
| `join?code=CODE` (also `lumora://together/CODE`) | a friend's Focus together room |

Links only navigate. A focus link never starts a session or quiets apps; that takes the
Start button. While a session runs, links other than an invite are ignored. A link opened
before onboarding is followed once it's done.

Taps: Today progress and Daily goal widgets open the focus setup, Rhythm opens Insights,
the Universe and StandBy widgets open the Universe. The daily invitation (on by default, 18:00,
sent only on days without a focus yet, queued two weeks ahead and topped up whenever the app
opens) carries `lumora://focus` in its userInfo and opens the
focus setup; a rare-event note opens Today. Shared cards (universe, year, achievements) carry
the landing page link.

The web side lives in the `basoglufurkan/mobapptech.com` repository: the
`.well-known/apple-app-site-association` file (every `/lumora` path except `/lumora/assets/`),
one page per path under `/lumora/`, and the download page at `https://www.mobapptech.com/lumora/`
in the app's 13 languages (Arabic right to left; `?lang=xx` picks one). The download page is a
universal link too: with Orbi installed, tapping it opens the app; otherwise it offers the
App Store. Once the app is live, set its App Store ID in `lumora/assets/config.js` (every page
reads it from there) and uncomment the `apple-itunes-app` meta tag in `lumora/index.html` for
Safari's Open/Get banner.

## Sign in with Apple

Optional; Orbi works fully without an account.

- **Onboarding** offers "Continue with Apple" beside "Start without an account";
  **Settings › Account** signs in later or signs out.
- **No server.** `AppleAccount` requests only the full name (never the email), keeps the
  Apple user ID in the iCloud Keychain (`KeychainItem`, synchronizable), and uses the given
  name for the universe if it has none. The ID is checked with Apple on launch and on
  `credentialRevokedNotification`; a revoked ID signs out. Signing out leaves the universe
  untouched.
