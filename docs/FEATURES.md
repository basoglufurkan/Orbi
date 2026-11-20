# Features

What Orbi does and how each part behaves. For how the code is organized, see
[ARCHITECTURE.md](ARCHITECTURE.md).

- [Screens](#screens)
- [Rewards](#rewards)
- [Siri, Shortcuts and Focus filters](#siri-shortcuts-and-focus-filters)
- [Tasks](#tasks)
- [Day plan and Today's orbit](#day-plan-and-todays-orbit)
- [Habits](#habits)
- [The Odyssey](#the-odyssey)
- [Focus together](#focus-together)
- [Pell, the companion moon](#pell-the-companion-moon)
- [Orbi+](#orbi)

## Screens

Five tabs sit behind the floating orbit bar:

- **Today**: the living universe, framed into the space between the
  greeting and the cards, with today's minutes and rhythm and **Begin
  Focus** beneath it. Nothing else sits over the sky.
- **Plan**: the day in one place. Today's orbit (what's now or next, the
  day's route, focus in one tap), today's habits as stars to keep in a tap,
  and today's tasks. Each section's **See all** opens its full sheet, and
  **+** adds a block, a task or a habit.
- **Universe**, **Odyssey** and **Insights**. The Collection of cosmic
  artifacts opens over Insights (also from Today's latest artifacts and
  `lumora://collection`).

Scrolling screens fade into the sky under the orbit bar instead of showing
their cards around it.

## Rewards

Every completed focus session adds to the sky. The rules live in `RewardRules`
and are all configurable.

| Trigger | Reward |
|---|---|
| Completed session, or ended early after ≥ 5 min | 1 star. Hue and shape come from the category; size grows with duration (ended early: 60%) |
| Every 4 stars on the same day | A constellation |
| 10 / 60 / 120 / 200… qualifying sessions | Planets: Velora, Ostra, Calyx, Thessa… |
| 30 / 90 / 160… sessions | A moon captured by the newest planet |
| Each full week of rhythm | A nebula (Rose Veil first) |
| 5 / 25 / 50 / 100… focus hours | A comet |
| 25 / 60 / 200 sessions | New regions open (Rose Veil, Ostra's Reach, Outer Drift) |

The rhythm (streak) allows one free rest day per rolling week. A second miss
pauses the rhythm; it never removes objects.

## Siri, Shortcuts and Focus filters

A focus session can start, pause, resume and end without opening the app.

| Intent | Parameters | App Shortcut phrases (examples) |
| --- | --- | --- |
| `StartFocusIntent` — Start Focus | `minutes` (optional, 5–180, clamped), `category` (optional) | "Start a focus in Orbi", "Start a coding focus in Orbi", "Focus with Orbi" |
| `StartTimedFocusIntent` — Start Timed Focus | `length` (15, 25, 45 or 60 min), `category` (optional) | "Start a 25 minute focus in Orbi" |
| `PauseFocusIntent` | — | "Pause my focus in Orbi" |
| `ResumeFocusIntent` | — | "Resume my focus in Orbi" |
| `EndFocusIntent` | — | "End my focus in Orbi" |

- **App Shortcuts.** `LumoraShortcuts` registers all five, so they appear
  under Orbi in the Shortcuts app and in Spotlight, work with Siri, and
  can be assigned to the Action Button with no setup. Phrases can only
  interpolate enums, which is why the spoken-length shortcut uses its own
  `FocusLength` preset instead of free minutes.
- **Defaults.** A missing length uses the default focus length from
  Settings. A missing category uses the active Focus filter's category, and
  then the last category used. As with the setup screen, starting a session
  remembers its category and ambience.
- **Guards.** "Start" while a session runs answers "already running" and
  keeps the session. Pause, resume and end are no-ops with a short reply
  when there's nothing to act on. Before onboarding, Start asks the user to
  open Orbi first. A session that finished while the app was suspended is
  completed (and rewarded once) before the intent acts.
- **Live Activity buttons.** The Lock Screen and expanded Dynamic Island show
  a pause button while focusing and a resume button while paused
  (`Button(intent:)`). The widget extension can't open the SwiftData store,
  so the control intents are `LiveActivityIntent`s: the system runs them in
  the app's process. The widget build compiles their bodies out
  (`WIDGET_EXTENSION`), and the app updates the activity through the usual
  `TimerEffectsCoordinator` path.
- **Start runs in the background.** `StartFocusIntent` is also a
  `LiveActivityIntent`, so the Live Activity can begin without opening the
  app. Opening Orbi afterwards shows the running session.
- **Focus filter (`LumoraFocusFilter`).** In Settings → Focus → (for example)
  Work → Add Filter → Orbi, choose a category and an ambience. While that
  Focus is on, the setup screen and Start intents use them; when it turns
  off, the system clears them and your own last choices apply again. The
  preset lives in the app's `UserDefaults`, not in SwiftData, so turning a
  Focus on or off never touches your history.

## Tasks

Plan what you'll focus on, then choose a task when a session begins.

- **Where.** Plan lists today's tasks; its **See all** (or `lumora://tasks`)
  opens **Tasks**, a sheet with three sections:
  - **Today**: tasks with no day, or whose day is today or has passed. A
    passed day reads "Since Oct 18" in quiet text. Nothing is ever marked
    overdue.
  - **Upcoming**: tasks planned for a later day, in date order. They move
    into Today when the day comes.
  - **Completed**: most recent first, and collapsible.
- **Editing.** The add and edit sheet has a title, a category (shape and hue
  chip), an estimate stepper (1–12 sessions, with the minutes it implies), an
  optional project or list name (existing names appear as chips), an
  optional day, and notes. Editing also offers Mark as done / Reopen and
  Archive.
- **Row actions.** Swipe right to complete or reopen. Swipe left to archive
  or edit. Use **Reorder** (or drag) to change Today's order. Archiving hides
  the task but keeps its sessions and stars.
- **Rows.** Each row shows the category glyph, the project tag and day,
  sessions-done / estimate orbs, and focused minutes. VoiceOver reads each
  row as one element ("Essay draft, Study, Thesis, 1 of 4 sessions,
  25 minutes, planned for tomorrow"). The start button is a separate
  element.
- **Starting from a task.** The play button on a row opens the setup screen
  with the task chosen. Setup also has **Choose from your tasks** (Today and
  Upcoming). Choosing a task fills in the intention and category and sets
  `FocusConfiguration.taskID`. The card then reads "Session 2 of 4 for Essay
  draft". Free-text intentions and the recent-intention chips work as before.
  Editing the text away from the task's title unlinks it.
- **After the session.** The summary shows "2 of 4 sessions for Essay draft"
  with progress orbs. Once the estimate is reached, it offers **Mark task
  done?**. "Start another session" keeps the same task chosen. Too-short
  sessions don't show the card, because they don't count.
- **Data.** `FocusTask` gained only defaulted or optional properties:
  `isPlanned`, `notes`, `estimatedSessions`, `dueDate` (stored as the start
  of its day), `isCompleted`, `completedAt`, `sortOrder` and `listName`.
  This is schema 1.1.0, an inferred lightweight migration that is still
  CloudKit-compatible. A store from the previous build opened with its
  history intact.
- **Progress is derived, never stored.** `TaskProgress` counts a task's
  linked, star-earning sessions and their focused minutes. `RewardService`
  still links sessions by `taskID` (or by title and category for free text)
  inside its exactly-once transaction. The reward's `TaskSnapshot` is rebuilt
  from persisted data like the rest of `SessionReward`.
- **Planned tasks vs. remembered intentions.** Intentions typed in setup are
  still remembered implicitly (`isPlanned == false`). They don't appear in
  the task list, and Settings' "forget intention" list now shows only these.

## Day plan and Today's orbit

Plan the day hour by hour, then follow it as a route through space.

- **Blocks are tasks.** A block ("09:00–10:30 Write the report") is a planned
  `FocusTask` with a time: `scheduledStart`, `scheduledMinutes` and its
  reminder choices (schema 1.6.0, all optional or defaulted). Its day is its
  due day, so it also shows in Tasks (with its time), its focus sessions
  count toward it like any task's, and lighting it is completing it. There is
  no second to-do system. `PlanBlock` and `DayTimeline` (in `Shared/`) are the
  pure, value-type picture the app, widgets and tests share.
- **Plan your day** (Plan's orbit section, or the orbit's planner button): a day
  strip for the coming week, a summary with **Running late?** (push the rest
  of today 5, 15 or 30 minutes), and a timeline of blocks with a live "now"
  line. Free time between blocks reads "1h 30m free" and tapping it plans a
  block there. Drag to reorder: the day re-flows, keeping each block's length
  and the gaps between them (`DayPlanner.repack`). Swipe to light, edit or
  delete. Unscheduled tasks sit on a shelf to be given a time.
- **The block editor:** title (or one of your tasks), start, end or a length
  chip, day, category, an overlap warning, and reminders: a notification
  0/5/10/15/30/60 minutes before, one as it begins (with a **Begin focus**
  action), and on iOS 26.1+ **Ring as an alarm** (AlarmKit, rings through
  Silent mode and Focus; its **Focus** button opens Orbi and begins).
  A new block suggests the next free slot and remembers the last reminder
  choice.
- **Today's orbit** (full screen, from Plan's orbit card or `lumora://plan`): a
  countdown to the end of what's now or the start of what's next, and the day
  as a serpentine route from dawn to night. The travelled road glows violet to
  gold, the road ahead drifts in dashes, upcoming stops breathe, the running
  stop sends out sonar rings with its time filling a ring, lit stops burn as
  their category's star (with a burst of light when lit while watching), and a
  comet marks now: circling the stop while its block runs, travelling between
  stops in step with the free time (`DayTimeline.cursor`). Reduce Motion (or
  Minimal motion) stills all of it.
- **One tap to focus.** The play button on a row, Plan's orbit card or the
  orbit starts a session on the block right away: the usual length, never
  longer than what's left of the block; "focus through the whole block" is
  one tap too. The session is linked to the block's task.
- **Everywhere else.** The **Today's orbit** widget (small, medium, Lock
  Screen rectangular and inline) shows what's now or next with a live
  countdown and the day's stops, with a timeline entry at every block start
  and end. The focus Live Activity shows the next block beneath the
  countdown. Reminders and alarms are rescheduled after every task change,
  when Orbi comes forward and when iCloud brings changes (at most 30
  notifications and 12 alarms, soonest first, eight days ahead).

## Habits

Daily discipline, drawn as stars. Each habit burns as a star that brightens
with its run, from an **ember** through spark, glow, star and giant to a
**nova** at 66 days (about how long a daily habit takes to become automatic).

- **The model.** `Habit` and `HabitCheckIn` (schema 1.7.0: two new entities,
  every property defaulted, the relationship optional, so the store upgrades by
  inference and stays CloudKit-compatible). A check-in is one kept day, stored
  as its local `DayKey`, so a streak never shifts when travelling. Streaks,
  the heat map and brightness are derived, never stored.
- **Schedules** (`HabitCadence`): every day, chosen weekdays, or N times a
  week. Pure math in `Shared/HabitSchedule.swift` (`HabitStats`,
  `HabitCalendar`, `HabitLuminosity`): due days count when kept and end a run
  when missed; days off never break it (and count if kept anyway); today,
  still open, never breaks it; a weekly target counts weeks, with the week
  starting where the person's calendar starts it. Days are counted noon to
  noon, so daylight-saving days are one day.
- **The Habits sheet** (Plan's **See all**, or `lumora://habits`): today's
  habits circle a core of light that grows brighter with each one kept, with
  beams of light running in from the kept ones. Each row is the habit's star
  (tap to keep, a burst of sparks), its streak, a status line ("Keep your
  8-day streak alive"), and the last seven days. Habits resting today and
  archived ones sit below. An empty sheet offers eight templates.
- **A habit up close:** its constellation (the last fourteen due days, seeded
  by the habit, kept days joined by light), its stage and the days to the
  next, current/best/total/30-day numbers, a focus card, and an 18-week heat
  map where a forgotten day can still be logged with a tap.
- **Focus keeps habits.** A habit can ask for N minutes of focus (in one
  category, or any). Every recorded session credits them; reaching the
  minutes keeps the habit by itself, and the session's summary says so
  ("Habit kept"). The play button starts a session for the minutes still
  missing, with the habit as its intention.
- **Plan and the day plan.** Plan shows today's habits as stars to keep in
  one tap (tap a name to open it, long-press to edit it or focus on it);
  Today's orbit shows them beside the day's route.
- **Reminders** at a chosen time, only on days the habit is still open (kept
  days, days off and weeks that reached their target stay quiet), with a
  **Mark as done** action that keeps it without opening the app. At most 14
  queued, soonest first, a week ahead; rescheduled after every change.
- **The Habits widget** (small, medium, Lock Screen circular and rectangular)
  keeps a habit with a tap (`ToggleHabitIntent`, run in the app's process)
  and resets at midnight on its own.
- Reduce Motion (or Minimal motion) stills the ring, the constellation, the
  breathing halos and the sparks.

## The Odyssey

A game layer on top of focus. It is built so that nothing in it can be
lost, duplicated or bought with money.

- **Stardust.** You earn one stardust per focused minute, plus 5 for each
  completed session. Earned stardust is always recomputed from stored
  sessions. Spending goes through an idempotent ledger: each purchase has a
  key, so the same purchase can never be charged twice.
- **Worlds.** Procedural sci-fi planets emerge as your total focus grows.
  The first appears at 50 minutes, and each later one needs a little more
  focus than the last, so there is always one just ahead. There are 12
  classes:
  - verdant, ocean, crystal, ember, glacier, gas giant, clockwork, shattered,
    twin, phantom, dune and reef;
  - plus a legendary Ringworld, Dyson Pearl or Living Eye on every 9th world.

  Each world is generated deterministically from its number (`WorldGenerator`):
  name, palette, rings, moons, stats, lore and a discovery.
- **Galaxies.** Each galaxy holds 6, then 8, then 10… worlds. When one is
  full the next ignites. The first ten have names (Lumen Spiral, Aurelian
  Ring, Velvet Maw…) and come in six shapes; after that they are generated.
- **Expeditions.** You plot a course, and your rocket travels while you
  focus. The journey takes 25–100 minutes of focus, across one or more
  sessions. Progress is the sum of focus recorded after launch. Arrival
  plays a landing cinematic and reveals the world's lore and a find for
  the Codex. The first journey is free, and recalling the ship refunds
  its fuel in full.
- **Terraforming.** Five stages: Breath, Flow, Bloom, Lights and Wonder. Each
  one visibly enriches the world, and the screen always shows a
  "now → next" preview of the next stage.
- **Horizons.** Goals you choose: weekly hours, worlds to chart, terraform
  stages, sessions or rhythm days. Reaching one pays out stardust. A weekly
  horizon that runs out simply rests; there is no penalty.
- **Rare events.** One a week, on a day chosen by a stable hash of the week
  (`CosmicCalendar`), so everyone shares the calendar: 11 kinds, from the
  Veyra Comet and the Ember Shower to the Great Alignment, a solar storm,
  a pulsar, a halo round the moon and a nebula blooming. Focusing that day
  witnesses it (stardust and a Codex line). A note arrives at 9:00 on the
  day (Settings › Notifications › Rare events); the next four weeks are
  scheduled whenever the app comes forward.
- **Ranks and the hangar.** Eight navigator ranks, from Cadet to Keeper of
  Many Skies, earned through experience. The hangar sells 4 hulls, 5 paints
  and 4 engine trails for stardust; some unlock only by rank.
- **Integration.**
  - Today shows the journey or the next world.
  - Focus setup shows what the session will power.
  - The focus screen shows minutes to arrival.
  - The completion summary shows stardust earned, new worlds and a "Land" button.
  - The universe widget shows the ship's progress.
- **Code.**
  - Logic: `Lumora/Services/Odyssey/` (`OdysseyService`, `OdysseyRules`, `WorldGenerator`, `GalaxyCatalog`, `WorldLexicon`).
  - Art: `Lumora/Animations/Odyssey/` (`WorldPainter`, `GalaxyPainter`, `RocketPainter`, cinematics).
  - Screens: `Lumora/Features/Odyssey/`.
  - Persistence: `OdysseyModels.swift` (schema 1.2.0, new entities only).
- **Debug:** `-lumora-gallery` (optionally `-lumora-gallery-section worlds|stages|galaxies|ships`)
  shows every world class at every stage, every galaxy and every ship.

## Focus together

Up to eight people focus in one room. While they do, the focus screen becomes a shared
galaxy with everyone in it as an astronaut at their own desk; desks appear as people
arrive and drift away as they finish or leave. Afterwards a bridge of light joins their stars.

- **Rooms live in CloudKit's public database** (`iCloud.com.mobapptech.lumora`), so there is
  no server to run. Records are addressed by name: `room-CODE` (owned by the host, seat 0)
  and `member-CODE-1` … `member-CODE-7` (one per friend's seat). Each device writes only its
  own record (`.changedKeys` patches) and reads the rest in one `records(for:)` call, so no
  query indexes are needed. The `FocusRoomMember` type now also has `seenAt` and `leftAt`.
- **Flow:** the host opens a room from the setup screen and shares `https://www.mobapptech.com/lumora/join/?code=CODE` (a universal link; the page falls back to `lumora://together/CODE`)
  (or just the 6-character code; ambiguous characters are left out). Friends take the first
  free seat. The host presses Start and everyone in the lobby begins at `startsAt` (three
  seconds ahead); anyone joining later begins on arrival, for the room's length.
- **Presence:** every device says "still here" (`seenAt`) every 20 s while it polls the room
  (1.5 s in the lobby, 6 s while focusing). Someone is in the galaxy until they finish
  (`doneAt`), leave (`leftAt`), or go quiet for 75 s (app closed, no connection). A relaunch
  mid-session takes the same seat again (`lumora.together.active` in `UserDefaults`).
- **The galaxy** (`Features/Together/`): `TogetherGalaxy3D` is RealityKit on iOS 18+, built
  from primitive meshes only (a 1,400-point spiral, a lit core, and per seat a platform, desk,
  glowing laptop and astronaut with a name label). The camera backs off until the widest row
  fits; three desks to a row on phones, four on wide screens, two rows beyond that.
  `TogetherGalaxy2D` draws the same room with Canvas and shapes on iOS 17
  (`-lumora-together-2d` shows it on newer systems in DEBUG).
- **Privacy:** only a first name, the session length and when someone starts, finishes or
  leaves leave the device, and only to the people with the code. Rooms expire after four
  hours. The privacy manifest declares the name (app functionality, not linked, no tracking).
- **Testing:** `TogetherService` runs against `LocalTogetherBackend` in unit tests, and the
  debug flag `-lumora-together-demo` fills the room with simulated friends (Ece, Mert, Ayla,
  Deniz) two seconds apart; the last one leaves after twenty seconds. Before release, deploy
  the CloudKit schema (new fields and record names) to Production.

## Pell, the companion moon

Designed in Figma ("Lumora — Pell character": a `Pell` component set with
one `Expression` variant per face) and drawn in code from the same geometry
(`PellPainter`, `Lumora/Animations/PellCharacter.swift`): calm, happy,
focused, sleepy, proud, curious and resting.

- `PellFace` floats, blinks every few seconds at irregular but repeatable
  moments, and cross-fades between faces; it holds still with Reduce Motion.
- On the break screen Pell is proud for the first four seconds (a star was
  just born), then calm (sleepy on a long break). Breathing with Pell opens
  its eyes on the in-breath and closes them on the out-breath, swelling
  slightly in time with the guide. Tapping Pell makes it smile (with a light
  haptic); VoiceOver reads its mood and offers the same action.
- The break-complete screen shows Pell happy.
- Pell also keeps the empty screens company: curious in Insights, the
  Collection and the Codex, happy in Tasks, sleepy on a world that hasn't
  formed, and beside "You did it." on the summary (proud, or delighted when
  that session met the day's goal).
- Debug: `-lumora-gallery -lumora-gallery-section pell` shows every face.

## Orbi+

Orbi+ is the optional upgrade, sold through RevenueCat (`Lumora/Services/Store/PlusStore.swift`).
The core stays free: stars, the universe, the Odyssey, Year in review and focusing together.
Stardust is never sold; Orbi+ finishes still cost stardust.

| Feature | Free | Orbi+ |
|---|---|---|
| Sky themes (`SkyTheme`) | Classic | Aurora, Ember, Ocean, Eclipse |
| Ambience (`AmbientSound`) | Silence, deep space hum, brown noise | Rain, tides, solar wind, campfire |
| Ship (`ShipPart.isPlus`) | Every hull, paint and trail so far | Eclipse and Opal paints, Supernova trail |
| Insights | This week and this month | Any earlier week or month, CSV export |

- **Products**: `com.mobapptech.lumora.plus.monthly`, `…plus.yearly` (subscription group "Orbi+"),
  `…plus.lifetime` (non-consumable). Entitlement `plus`, offering `default`.
- **State**: `PlusStore` listens to RevenueCat's customer info and mirrors the answer into the app group
  (`PlusAccess`), so it holds offline and at launch. When Orbi+ ends, the chosen theme, sound and
  finishes quietly fall back to the free ones; nothing bought with stardust is taken away.
- **Paywall** (`PlusPaywallView`): from Settings › Orbi+, any locked item (it opens with that feature
  first) and `lumora://plus`.
- **API keys** come from `Config/Secrets.xcconfig`, which isn't in the repository (see
  [Configuration](DEVELOPMENT.md#configuration)). DEBUG builds use RevenueCat's Test Store key (`test_…`), so
  purchases are simulated with no App Store Connect setup. Release builds need the App Store key (`appl_…`); a
  Test Store key in a submitted build gets it rejected.
- **Without an API key** `PlusStore` stays off; DEBUG builds show sample prices so the paywall can be
  designed. `-lumora-plus 1` (or `0`) forces Orbi+ on or off in DEBUG.
- **After onboarding** (`PlusIntroOfferView`), once: the yearly plan's free trial as a timeline (today, a
  reminder notification two days before the end, the first charge). Closing it offers Orbi+ for life; closing
  that leaves the regular paywall to Settings, locked items and `lumora://plus`. No trial to give → the regular
  paywall. `-lumora-intro-offer` shows it again in DEBUG.
