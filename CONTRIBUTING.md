# Contributing to Orbi

Thanks for helping. Bug reports, fixes and ideas are all welcome. For
anything bigger than a small fix, please open an issue first so we can agree
on the approach before you put time into it.

## Setting up

Follow [Getting started](README.md#getting-started). The simulator needs no
keys or signing setup, and the [debug launch
arguments](docs/DEVELOPMENT.md#debug-and-preview-tools) seed a sky, a day plan
and habits in one go. [ARCHITECTURE.md](docs/ARCHITECTURE.md) is the best
place to start reading the code.

## How the code is written

- **Swift 6 with strict concurrency, and no warnings.** The project builds
  without a single warning; please keep it that way.
- **One direction of data.** Views read the `@Observable` `AppModel`, which
  owns the services; services own their SwiftData writes. Put logic in pure
  engines (no state of their own, time passed in) and test it there.
- **Time comes from the clock.** Logic takes the time from the app's
  `DateProvider` (`ManualDateProvider` in tests) rather than calling `Date()`,
  so tests can move time and the timer stays derived from dates.
- **The universe is deterministic.** Anything that places or shapes the sky
  uses `SeededRandom` seeded from stable IDs, so replaying history redraws the
  same sky. Don't reach for the system random generator there.
- **Use the design system.** `LMColor`, `LMFont`, `LMSpace`, `LMSpring` and
  the shared components (`.glassCard`, `CosmicButton`, …) instead of raw
  colors, sizes and animations. Colors work in both the Night and Dawn themes.
- **Accessible by default.** Every control has a label, decorative images are
  hidden from VoiceOver, targets are at least 44 pt, layouts hold up to
  Dynamic Type AX5, and Reduce Motion stills what moves.
- **Every string in 13 languages.** New user-facing text goes into the right
  String Catalog with all twelve translations (see
  [Localization](docs/DEVELOPMENT.md#localization)).
- **CloudKit-compatible models.** SwiftData changes are additive: new
  properties have defaults or are optional, relationships are optional, there
  are no unique constraints, and each change gets a new schema version.
- **Privacy first.** Analytics events are cases of `TelemetryEvent` and never
  carry anything a person typed. New events also go into
  [ANALYTICS.md](docs/ANALYTICS.md).

## Tests

Run the unit tests before you open a pull request, and the UI tests when a
flow changes; [TESTING.md](docs/TESTING.md) has the commands. New logic comes
with Swift Testing tests next to the existing ones in `LumoraTests/`.

## Commits and pull requests

- One logical change per commit, with a message that names the area and says
  what changed in plain words, for example
  `Day plan: sync reminders and widgets at launch`.
- Keep pull requests focused and fill in the template: what changed, why, and
  how you tested it. For UI changes, add before and after screenshots.
- Never commit keys or personal data. `Config/Secrets.xcconfig` and
  `GoogleService-Info.plist` are ignored by git for that reason.

## Reporting bugs and security issues

Use the issue templates for bugs and ideas. Please report security problems
privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md),
and you agree that your contributions are licensed under the project's
[MIT License](LICENSE).
