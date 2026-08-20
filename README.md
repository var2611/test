# Wattson ⚡️

**A menu bar power companion for Apple silicon MacBooks.**
Wattson tells you whether your Mac is running on the battery or the adapter, how many
watts it is actually burning, and how healthy the cell is — and does it with a
cartoon character who sips electricity through a straw while charging and puts on
sunglasses at 100%.

<!-- Screenshots go here once the app has been built and run on a Mac. -->

---

## What it does

| | |
| --- | --- |
| **Live source** | Battery, adapter, charging, charging-paused, fully charged — updated the instant the cable moves, not on the next tick. |
| **Real watts** | System draw in watts, **measured** from the cell on battery and **estimated** from the adapter's negotiated envelope while plugged in. Every figure carries which one it is. |
| **A mascot with opinions** | Eleven moods driven by the actual numbers: sipping, guzzling, smug, napping, chill, working, turbo, sweating, panicking, power-saving, ghost. |
| **The corner runner** | Click the menu bar mascot and a character sprints along the bottom-left or bottom-right of your screen at a stride rate proportional to your live power draw. |
| **History** | Wattage and charge level over 1 h to 30 days, with average, peak, energy in watt-hours, and a discharge rate in %/hour. |
| **Health** | Cycle count, maximum capacity against design, temperature, condition, with a plain-language grade. |
| **Adapter detail** | What is plugged in, and what it actually negotiated — a 96 W brick delivering 20 W is a thing you want to know about. |
| **Diagnostics** | A searchable view of every property the `AppleSmartBattery` node publishes. |

---

## Getting it running

```bash
# Unit tests for all of the decision logic — no Xcode required
swift test

# Generate the Xcode project and build the app (macOS + Xcode 15 or later)
brew install xcodegen
make project
make build
make run
```

To develop the UI without draining a real battery, run the app with `--simulate`
(or `WATTSON_SIMULATE=1`), which drives every view from a scripted power source that
cycles through discharging, charging and fully-charged.

Regenerate the app icon at any time with `make icon`.

### Before submitting to the App Store

1. Set `DEVELOPMENT_TEAM` in `project.yml` (or configure signing in Xcode).
2. Create the three products in App Store Connect with the IDs in
   `App/Store/StoreManager.swift` → `ProductID`, in a subscription group called
   *Wattson Pro*.
3. Attach `App/Resources/Wattson.storekit` to the scheme for local testing, and detach
   it before archiving.
4. Work through [`docs/APP_STORE.md`](docs/APP_STORE.md).

---

## How the numbers are produced

Wattson uses **only public, sandbox-safe APIs**. No private frameworks, no `IOReport`,
no SMC pokes — those would give per-core wattage but they are a guideline 2.5.1
rejection waiting to happen.

* `IOPowerSources` — charge level, source, charging flags, macOS's own time estimates.
* The `AppleSmartBattery` IORegistry node — terminal voltage, signed current,
  capacities, cycle count, temperature and the attached adapter's negotiation.

From those:

| Situation | System draw | Confidence |
| --- | --- | --- |
| On battery | `−(V × I)` — everything the machine burns leaves the cell | **measured** |
| Charging | `adapterNegotiated − batteryChargePower` | *estimated* |
| Full / paused | `adapterNegotiated` (no current through the cell to measure) | *estimated* |

The distinction is shown in the UI on every reading, with a tooltip spelling out the
arithmetic. An estimate presented as a measurement is the difference between a tool
and a toy.

---

## Layout

```
Sources/WattsonCore/   Pure Swift: models, wattage maths, history, moods, alerts,
                       entitlement matrix, formatters. No UI, no IOKit. Unit-tested.
Tests/                 ~90 tests over everything in WattsonCore.
App/                   The macOS app.
  Power/               IOKit reader (+ a simulator) and the monitor that drives the UI.
  MenuBar/             Status item, animated mascot, right-click menu.
  UI/                  Dashboard, settings, paywall, welcome, shared components.
  Runner/              The corner overlay panel and its procedural characters.
  Store/               StoreKit 2.
  Services/            Preferences, history persistence, notifications, export, login item.
docs/                  Plan, architecture, App Store checklist, privacy.
```

Everything the app draws — mascot, runners, gauges, sparklines — is drawn
procedurally in `Canvas`. There are no sprite sheets: the art is crisp at 18 pt in
the menu bar and at 180 pt in the dashboard, recolours instantly for skins and for
light/dark, and costs one draw call.

---

## Free vs Pro

The free app is a complete, useful app: live source, charge state, measured watts,
time remaining, the full mascot, the runner, and battery health. Pro adds skins,
30-day history, custom alerts and quiet hours, deep diagnostics, export, and menu bar
customisation.

There is **no account and no server**. Entitlement comes from
`Transaction.currentEntitlements`, which the App Store already ties to the user's
Apple Account and Family Sharing. Nothing about the machine ever leaves it — see
[`docs/PRIVACY.md`](docs/PRIVACY.md).

---

## Requirements

macOS 13 or later. Apple silicon is the target; Intel MacBooks work, with the
silicon-specific copy hidden. Built with Swift 5.9 / Xcode 15.
