# Architecture

## The split that matters

```
WattsonCore  — every decision, no dependencies, fully unit-tested
App          — every effect: IOKit, AppKit, SwiftUI, StoreKit, notifications
```

`WattsonCore` imports `Foundation` and nothing else. That is what makes the interesting
parts of this app testable on any machine: how watts are computed and how confident we
are in them, when an alert fires and when it is suppressed, how a snapshot becomes a
mood, how history is bounded and summarised, what the free tier includes.

The app layer is deliberately dull. It reads registries, draws pixels and posts
notifications; it makes no decisions of its own.

## Data flow

```
       ┌──── IOPSNotificationCreateRunLoopSource (cable moved) ────┐
       │                                                            ▼
Timer ─┴──▶ PowerMonitor.refresh()
                 │
                 ├─▶ IOKitPowerReader.read()   ──▶ PowerSnapshot (raw)
                 ├─▶ SnapshotSmoother          ──▶ PowerSnapshot (de-jittered)
                 ├─▶ MascotMoodResolver        ──▶ MascotMood
                 ├─▶ RunnerMotion.motion(for:) ──▶ RunnerMotion
                 ├─▶ HistoryStore.record(_:)   ──▶ PowerHistory (bounded, debounced to disk)
                 └─▶ AlertEngine.evaluate(_:)  ──▶ [AlertRequest] ──▶ NotificationService
                          │
                          ▼
              @Published state observed by
      MenuBarMascotView · DashboardView · RunnerView · SettingsView
```

One `PowerMonitor` exists for the process lifetime. Views observe it; nothing else
polls the hardware.

## Decisions worth knowing about

**Everything is drawn, not shipped.** The mascot and the six runner characters are
procedural `Canvas` drawings in a normalised coordinate space. No sprite sheets means
crisp art at 18 pt and 180 pt, instant recolouring per skin and per appearance, no
asset bundle to load at launch, and a diffable definition of the artwork.

**Confidence is a first-class value.** `DrawEstimate` carries `watts`, a
`MeasurementConfidence` and a plain-language `explanation`. The UI shows the badge and
the tooltip everywhere a wattage appears. This constrains the whole design — you cannot
quietly round an estimate into a fact when the type will not let you.

**Adaptive cadence.** Polling backs off on battery, speeds up on the adapter, and runs
at 1 s while the dashboard or the runner is open (`beginBoost`/`endBoost`). Timers
carry a 20% tolerance so macOS can coalesce the wake-ups, the run loop source reacts
instantly to a cable change so the interval never has to be short "just in case", and
sleep tears the timer down entirely.

**The overlay is a window, and it closes.** The runner lives in a non-activating,
click-through `NSPanel` that is ordered out — not hidden — when dismissed, so nothing
renders and the animation timeline stops when it is not on screen.

**Degradation, not failure.** Every IOKit property is independently optional with
multi-key fallbacks; a missing `Temperature` costs one row. If StoreKit is unreachable,
the paywall says so and the app carries on. If the history file is corrupt it is
replaced. If notification permission is denied the settings screen explains why the
switches do nothing. There is no state in which the app shows an error instead of a
battery level.

**Entitlement is checked, never trusted.** `VerificationResult` is unwrapped through a
single `verified(_:)` helper that returns `nil` for unverified transactions, revoked
and expired transactions grant nothing, and a lapse calls
`Preferences.downgradedToFreeTier()` so a paid setting can never linger past its
subscription.

## Testing

`swift test` covers `WattsonCore`:

* `PowerMathTests` — conversions, the three draw regimes, clamping, projections
* `SnapshotSmootherTests` — damping, reset on state change, missing readings
* `PowerHistoryTests` — ring bounds, pruning, downsampling, statistics, sleep gaps, CSV
* `MascotMoodTests` — the full mood matrix and its precedence rules
* `AlertEngineTests` — hysteresis, cooldowns, quiet hours across midnight, gating
* `PreferencesTests` — validation clamps, tolerant decoding, downgrade
* `EntitlementAndFormatTests` — the free/paid matrix and every user-facing string
* `RunnerMotionTests` — the watts-to-stride-rate mapping and its bounds

The app layer is verified by running it: `WATTSON_SIMULATE=1` drives every view from a
scripted power source that cycles through discharging, charging and fully-charged in
under a minute.
