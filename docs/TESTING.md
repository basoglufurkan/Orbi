# Testing

Most of Orbi's logic lives in pure engines (the timer, progression, layout,
the planners, insights), so most tests run without a UI. UI tests cover the
flows that matter end to end.

## Running the tests

Unit and integration tests:

```bash
xcodebuild test -project Lumora.xcodeproj -scheme Lumora \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:LumoraTests
```

UI tests read English labels, so run them in English whatever the
simulator's language:

```bash
xcodebuild test -project Lumora.xcodeproj -scheme Lumora \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:LumoraUITests -testLanguage en -testRegion US
```

Use any iPhone simulator you have installed. In Xcode, **Product › Test**
(⌘U) runs both. UI tests launch the app with `-lumora-ui-testing` and
`-lumora-time-scale 600`, so a 25-minute session takes about 2.5 seconds;
`-lumora-reset` gives each test a fresh install. `MarketingCaptureTests`
films the App Store captures and is skipped unless
`Marketing/Capture/capture.sh` runs it; `iPadWindowTests` runs only on an
iPad simulator.

GitHub Actions runs the unit tests on every push and pull request
([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)).

## What the tests cover

- **Unit and integration tests** (Swift Testing, `LumoraTests/`). They cover:
  - timer state transitions, pause and resume math, completion exactly at the deadline, and completion while inactive;
  - pausing right before or after the deadline, rapid double taps, auto-end after a long pause, and break and long-break cycles;
  - relaunch recovery, crash-safe exactly-once completion, and reward persistence;
  - constellation and planet progression, ended-early and too-short sessions, and that failures never erase progress;
  - midnight, month and year boundaries, time-zone changes, and the widget day rollover;
  - rhythm rules and achievements;
  - determinism of the stored universe versus replay, and no overlapping stars;
  - preference persistence, the SwiftData timer checkpoint, erase-all on an on-disk store, and export;
  - tasks: derived progress (only star-earning sessions count), linking a session by `taskID` updating progress (also when the intention text was edited), exactly-once recording, the summary's task snapshot after a relaunch, completion and reopening, archiving keeping sessions, Today/Upcoming sectioning without "overdue", manual reordering, draft trimming and clamping, and gentle due-day labels;
  - the day plan: now/next/status at any moment, the comet's place (approach, waiting, travelling, drifting home, a block lit early, overlaps), widget timeline boundaries, free-slot suggestions, overlaps, re-flow on reorder, "running late", focus length inside a block, sessions a block holds, reminder and alarm planning (lead times, the past, lit and silent blocks, alarms replacing the start notification, limits), blocks as planned tasks (whole minutes, due day, reminders, keeping the time when edited, removing it, rescheduling), plan links and notifications, old widget snapshots still decoding, the Live Activity's next block, and the route geometry;
  - habits: daily, weekday and weekly streaks (today never breaking a run, days off, best runs, the week start following the calendar, a logged day moving the start back), cadence storage, local midnight, daylight-saving days, kept days not shifting when travelling, day states for the heat map, brightness stages, reminders (open days only, weeks that met their target, the streak only on today's, the limit, identifiers), the store (keeping, reopening, future days refused, logging a past day, focus crediting by category, archive and delete), folding duplicate check-ins from two devices, and a 1.6 store opening with habits;
  - App Intents: default and clamped minutes, category precedence (explicit, then Focus filter, then last used), the Focus filter preset clearing when the Focus ends, "start" not replacing a running session, onboarding guard, and pause/resume/end keeping time derived and rewarding once;
  - deep links: parsing and building every path, in both the `lumora://` and the universal-link form, and where each one lands.
- **UI tests** (XCTest, `LumoraUITests/`). They cover:
  - onboarding → focus → completion → universe shows "1 star";
  - the star surviving an app relaunch;
  - pause, resume and end early;
  - universe gestures (drag, pinch, zoom buttons, region chips);
  - creating a task on Plan → choosing it in setup → the summary showing "1 of 2 sessions for Essay draft";
  - a habit from a template, kept and reopened with a tap, then kept by focusing on it (the summary says "Habit kept");
  - the Odyssey loop: a world forms from earlier focus, a course is plotted and launched, a session powers the
    journey and the ship lands.

## Manual checks

Things the automated tests can't see were checked by hand in the iOS
Simulator, on screens from the iPhone SE (3rd generation) to the largest
iPhones:

- **Languages and themes.** English and Turkish throughout; Arabic (right to
  left) and German for layout; the Night and Dawn themes.
- **Accessibility.** Dynamic Type up to AX5 on the iPhone SE: screens that
  can't fit scroll instead, rows and buttons stack, nothing truncates or
  overlaps. VoiceOver labels and traits were checked through the
  accessibility tree and `performAccessibilityAudit`, and small targets
  enlarged to 44 pt. Increase Contrast, Reduce Transparency and Reduce Motion
  switch to solid surfaces, brighter hairlines and still scenes.
- **App Intents end to end.** The Shortcuts app lists Orbi's App Shortcuts;
  with Orbi terminated, "Start Focus" launched it in the background and
  started the Live Activity, whose pause and resume buttons acted on the same
  session. (See the signing note in [DEVELOPMENT.md](DEVELOPMENT.md#app-shortcuts-in-the-simulator).)
- **Upgrades.** A store written by an earlier build opens with its history
  intact.
- **System surfaces.** Every widget family and the Live Activity states were
  placed on the simulator's Home and Lock Screens.

Not verified yet:

- frame rate and battery use on a real device;
- haptics and audible sound (the simulator has neither);
- notifications, reminders and alarms actually firing, including the habit
  reminder's Mark as done action;
- the Live Activity's minimal Dynamic Island form and its stale and complete
  states, live;
- interactive widgets placed on a Home Screen (keeping a habit from the
  widget);
- iCloud sync between two devices;
- navigating the whole app by ear with VoiceOver on a real device.
