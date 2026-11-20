# Development

Everything needed to build Orbi, run it on a device, and use the debug
tools. For an overview of the code, start with
[ARCHITECTURE.md](ARCHITECTURE.md).

- [Requirements](#requirements)
- [Configuration](#configuration)
- [Running on a device](#running-on-a-device)
- [Debug and preview tools](#debug-and-preview-tools)
- [App Shortcuts in the simulator](#app-shortcuts-in-the-simulator)
- [Localization](#localization)
- [Scripts](#scripts)

## Requirements

- Xcode 26.1 or later (built and tested with Xcode 27.2)
- iOS 17.0 or later on iPhone and iPad; watchOS 10.0 or later for the Watch app
- Swift 6 language mode with strict concurrency checking

Swift Package Manager fetches the two dependencies on the first build:
[RevenueCat](https://github.com/RevenueCat/purchases-ios-spm) and
[Firebase](https://github.com/firebase/firebase-ios-sdk) (Analytics only).
The project uses Xcode's file-system-synchronized groups: new files under
`Lumora/`, `Shared/`, `LumoraWidgets/` or the test folders are picked up
without touching the project file.

## Configuration

The simulator needs no setup: open `Lumora.xcodeproj`, choose the **Lumora**
scheme and run. Two services are optional and stay off until you give them
keys, which never go into the repository:

| Service | Add | Without it |
| --- | --- | --- |
| Orbi+ purchases (RevenueCat) | Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and fill in the public SDK keys | Purchases are off; DEBUG builds show sample prices so the paywall can still be designed |
| Analytics (Firebase) | Your project's `GoogleService-Info.plist` in `Lumora/Resources/` | Firebase isn't started and nothing is sent |

`Config/Lumora.xcconfig` includes `Secrets.xcconfig` when it exists, and the
key reaches the app through the Info.plist (`RevenueCatAPIKey`). Debug builds
take RevenueCat's Test Store key (`test_…`), release builds the App Store key
(`appl_…`). See [Orbi+](FEATURES.md#orbi) and
[Analytics and privacy](ANALYTICS.md).

## Running on a device

The identifiers belong to the shipping app, so a build for your own device
needs your own:

1. In **Signing & Capabilities**, set your team on every target: `Lumora`,
   `LumoraWidgetsExtension`, `LumoraWatch`, `LumoraShieldMonitor`,
   `LumoraShieldConfiguration` and `LumoraShieldAction`.
2. Change the bundle identifiers (`com.mobapptech.lumora` and the
   extensions under it) to ones your team can register.
3. Change the shared identifiers:
   - App Group `group.com.mobapptech.lumora`: `Config/*.entitlements` and
     `Shared/AppGroup.swift`;
   - iCloud container `iCloud.com.mobapptech.lumora`:
     `Config/Lumora.entitlements` and `DataStore.cloudContainerID`;
   - associated domain `applinks:www.mobapptech.com` in
     `Config/Lumora.entitlements`, or remove it (universal links then won't
     open the app; `lumora://` links still do).

The Screen Time shield needs the `com.apple.developer.family-controls`
entitlement on the app and its shield extensions. Development builds get it
from Xcode; App Store builds only once Apple approves the distribution
request. It's switched by `FeatureFlags.distractionShield` and sits behind
the `DistractionShielding` protocol, so the rest of the app never depends on
it. iCloud sync needs a signed-in iCloud account; without one the app works
the same, locally.

## Debug and preview tools

Add these launch arguments under **Product › Scheme › Edit Scheme › Run ›
Arguments**. `-lumora-reset`, `-lumora-skip-onboarding`, `-lumora-in-memory`
and `-lumora-ui-testing` work in any build, so UI tests can also run against
a release build; the rest exist only in DEBUG builds.

| Launch argument | Effect |
| --- | --- |
| `-lumora-time-scale 300` | Speeds sessions up 300×, so 25 minutes takes 5 seconds |
| `-lumora-reset` | Erases all data on launch (a fresh install) |
| `-lumora-skip-onboarding` | Starts on Today with a named universe |
| `-lumora-demo 130` | Seeds 130 historical sessions through the real reward pipeline |
| `-lumora-demo-plan` | Seeds today's plan around now: a lit block, a passed one, one under way and three ahead |
| `-lumora-demo-habits` | Seeds five habits with weeks of history: kept, at risk, weekly, weekday and focus-linked |
| `-lumora-clock 10:20` | The app's clock starts today at 10:20 and runs on from there (day-plan screenshots) |
| `-lumora-in-memory` | Uses a throwaway store |
| `-lumora-fake-tilt` | Drives gyro parallax with a slow synthetic tilt (the simulator has no gyroscope) |
| `-lumora-plus 1` (or `0`) | Forces Orbi+ on (or off) regardless of purchases |
| `-lumora-intro-offer` | Shows the after-onboarding free-trial offer again |
| `-lumora-event-today <kind>` | Makes this week's rare event (a `CosmicEventKind`) happen today |
| `-lumora-together-demo` | Fills a Focus together room with simulated friends |
| `-lumora-together-2d` | Draws the Focus together galaxy in 2D (the iOS 17 version) on newer systems |
| `-lumora-gallery` | Shows the art gallery instead of the app; add `-lumora-gallery-section worlds`, `stages`, `galaxies`, `ships` or `pell` for one section |
| `-lumora-ui-testing` | Set by the UI tests: no iCloud, analytics, purchases, shield, splash or companion notes |
| `-FIRDebugEnabled` | Streams analytics events to Firebase › DebugView |

**Settings › Debug** also has a session-speed picker and a demo-data button.
Acceleration is clamped to 1× in release builds (`FocusTimerEngine.sanitized`),
so it can't affect production timing.

## App Shortcuts in the simulator

Xcode signs simulator builds ad hoc, and the system refuses to run App
Shortcuts from an app with no team ID ("Unable to run App Shortcut"). To try
them in the simulator, re-sign the built app with a development certificate
(`codesign --force --sign "Apple Development" --entitlements
Config/…entitlements`, extension first, then the app). Device builds signed
by Xcode don't need this.

## Localization

Orbi ships in 13 languages: English, Turkish, Arabic, German, French,
Spanish, Italian, Brazilian Portuguese, Russian, Japanese, Korean,
Simplified Chinese and Thai. They live in String Catalogs for the app,
the widgets and the Siri phrases.

- Arabic lays out right to left, and letter spacing is turned off for it so
  the script stays connected.
- Day keys are always Gregorian, so users on Islamic, Buddhist or Japanese
  calendars get correct "today" and rhythm logic.
- The translations are machine-produced and not yet reviewed by native
  speakers. Beyond English and Turkish, the UI was checked in the simulator
  in Arabic and German.

Every user-facing string needs all twelve translations when it's added.
The catalogs:

| Catalog | Holds |
| --- | --- |
| `Lumora/Resources/Localizable.xcstrings` | The app |
| `Lumora/Resources/InfoPlist.xcstrings` | Permission prompts and the display name |
| `Lumora/Resources/AppShortcuts.xcstrings` | Siri and Shortcuts phrases |
| `LumoraWidgets/Localizable.xcstrings` | Widgets, the control and the Live Activity |
| `LumoraWatch/Localizable.xcstrings` | The Watch app |
| `LumoraShieldConfiguration/Localizable.xcstrings` | The Screen Time shield |

## Scripts

Assets that are drawn in code are rendered by small scripts, so they can be
regenerated after a change:

| Script | Renders |
| --- | --- |
| `swift Tools/AppIcon.swift <out-dir>` | The app icon: Pell with its gold orbit and four-point star |
| `swift Tools/LaunchImage.swift <imageset>` | `LaunchPell`, the static launch screen |
| `swift Tools/IAPPromoImages.swift <out-dir>` | The three promoted In-App Purchase images |
| `python3 Marketing/Screenshots/compose.py` | App Store screenshots from raw simulator captures |
| `Marketing/Capture/capture.sh <lang>` | App preview clips, filmed by `MarketingCaptureTests` |
