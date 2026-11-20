# Analytics and privacy

Firebase Analytics (Google Analytics 4) through `Telemetry` (`Lumora/Services/Analytics/`). Every event is a case
of `TelemetryEvent`, so names and parameters live in one file and `TelemetryTests` checks them against GA4's rules.

- **Privacy**: the no-ad-ID SDK (`FirebaseAnalyticsCore`): no IDFA, no IDFV, no ad personalization, no SKAdNetwork.
  Nothing typed is ever sent (intentions, task titles, names, room codes). Settings › Your data › Share usage data
  turns it off.
- **Setup**: put your own `GoogleService-Info.plist` in `Lumora/Resources/` (it isn't in the repository). Without
  it Firebase isn't started and nothing is sent; tests, UI tests and in-memory runs never send. DEBUG builds print
  every event to the console (`com.mobapptech.lumora`, category `Telemetry`); add `-FIRDebugEnabled` to the scheme
  to watch them in Firebase › DebugView.
- **Revenue**: the app sends `begin_checkout` and `purchase` (GA4 e-commerce), so revenue reports work.
  Renewals, cancellations and refunds happen outside the app: turn on RevenueCat › Integrations › Firebase,
  which receives Firebase's install ID from `PlusStore`.

## Events

| Area | Event | Parameters |
| --- | --- | --- |
| App | `app_opened` | `days_since_install`, `universe_day` |
| | `screen_view` | `screen_name`: a tab (today, plan, universe, odyssey, insights) or a screen (collection, settings, tasks, habits, habit_detail, day_orbit, day_planner, focus_setup, focus_active, celebration, break, hangar, world_detail, year_review, together, sky_options, celestial_detail, paywall, intro_offer, onboarding) |
| | `deep_link_opened` | `target` (focus, plus, insights/year…), `link_type` (scheme, universal) |
| | `notification_opened` | `kind` (daily_invitation, cosmic_event, focus_complete, break_complete) |
| | `notification_permission` | `granted`, `source` |
| Onboarding | `onboarding_started`, `onboarding_step`, `onboarding_completed` | `step`; `name_given`, `apple_sign_in` |
| Focus | `focus_started` | `minutes`, `category`, `ambience`, `has_intention`, `from_task`, `shield`, `together`, `source` (app, task, link, notification, watch, shortcut, together, onboarding) |
| | `focus_paused` / `focus_resumed` | `elapsed_minutes`, `pause_count` |
| | `focus_completed` | `minutes`, `category`, `pauses` |
| | `focus_ended_early` | `planned_minutes`, `focused_minutes`, `category`, `pauses`, `percent_done` |
| | `focus_auto_ended` | `planned_minutes`, `focused_minutes` (a pause ran past 10 minutes) |
| | `ambience_changed` | `sound`, `during` |
| | `break_started` / `break_finished` | `minutes`, `long_break`; `skipped` |
| Rewards | `star_earned` | `category`, `minutes`, `star_number`, `today_stars` |
| | `session_without_star` | `focused_minutes` |
| | `constellation_formed`, `planet_born`, `moon_captured` | `constellations`; `planet_number` |
| | `achievement_unlocked` | `achievement_id`, `milestone` |
| | `daily_goal_reached` | `goal_minutes`, `today_minutes` |
| | `task_progressed` | `sessions_done`, `sessions_planned`, `completed` |
| Universe | `celestial_opened`, `universe_shared` | `kind` |
| | `sky_theme_changed`, `sky_option_changed` | `theme`; `option`, `on` |
| | `year_review_opened`, `year_review_shared` | `sessions` |
| Odyssey | `stardust_earned` | `amount` |
| | `world_emerged`, `galaxy_ignited` | `world_number`, `rarity`; `galaxy` |
| | `course_plotted`, `expedition_recalled`, `expedition_arrived` | `world_number`, `cost` |
| | `ship_part_bought`, `ship_part_equipped` | `part`, `price`, `plus` |
| | `horizon_started`, `horizon_reached` | `kind`, `target`; `chain` |
| | `rank_up`, `cosmic_event_witnessed` | `level`; `kind` |
| Tasks | `task_created`, `task_completed`, `task_archived` | `has_due_date`, `sessions`; `via_focus` |
| Day plan | `plan_block_saved` | `new`, `minutes`, `reminder_minutes`, `at_start`, `alarm` |
| | `plan_shifted`, `plan_focus_started`, `plan_orbit_opened` | `minutes`, `blocks`; `minutes`, `during_block`, `source`; `blocks`, `lit` |
| Habits | `habit_created`, `habit_checked_in` | `cadence`, `focus_minutes`, `reminder`, `template`; `source`, `streak`, `backfill` |
| | `habit_archived`, `habits_opened` | `days_kept`; `habits`, `kept_today`, `source` |
| Together | `together_room_created`, `together_joined`, `together_started`, `together_invite_shared`, `together_failed` | `minutes`; `via_link`; `role`; `reason` |
| Insights | `insights_period_changed`, `insights_history_browsed`, `csv_exported` | `period`, `periods_back`; `sessions` |
| Settings | `setting_changed` | `setting`, `value` (logged when Settings closes, one per changed setting) |
| | `icloud_sync_changed`, `apple_sign_in_completed`, `data_exported`, `data_erased`, `analytics_opt_out` | `on` |

## Orbi+ funnel

| Step | Event | Parameters |
| --- | --- | --- |
| Tapped something locked | `locked_feature_tapped` | `feature` (sky_themes, ambience, ship_finishes, history, export), `screen` |
| Saw the paywall | `paywall_viewed` | `source` (settings, locked_feature, link, onboarding_trial, onboarding_lifetime, onboarding), `feature`, `plans`, `availability` |
| Picked a plan | `paywall_plan_selected` | `plan` (yearly, monthly, lifetime) |
| Tapped buy | `begin_checkout` *(GA4)* | `value`, `currency`, `plan`, `item_id`, `item_name`, `source` |
| Paid | `purchase` *(GA4)* | the same, plus `transaction_id` |
| Started a free trial | `plus_trial_started` | the same with `value` 0, plus `price`, `trial_days` |
| Either of the two | `plus_purchase_completed` | the same, plus `trial` |
| Backed out / waiting / failed | `plus_purchase_cancelled`, `plus_purchase_pending`, `plus_purchase_failed` | `plan`; `error` |
| Restore | `plus_restore_started`, `plus_restore_completed`, `plus_restore_failed` | `found`; `error` |
| Left the paywall | `paywall_dismissed` | `source`, `seconds`, `purchased` |
| Status changed (start, expiry) | `plus_status_changed` | `from`, `to` |
| Other | `manage_subscription_opened`, `plus_offerings_failed` | `error` |

## User properties

`plus_status`, `appearance`, `ambience`, `daily_goal` (bucketed), `universe_size` (bucketed), `odyssey_rank`,
`icloud_sync`, `focus_shield`, `sky_theme`, `apple_sign_in`.
