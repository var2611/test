# Wattson — Product & Engineering Plan

> A menu-bar power companion for Apple Silicon MacBooks.
> Tells you *where your power is coming from*, *how fast it is going*, and makes you
> smile while it does it.

---

## 1. Product definition

**One-liner:** Wattson lives in your menu bar as a cartoon battery character. He knows
whether you are on battery or plugged in, how many watts the machine is pulling right
now, and he reacts — sipping electricity while charging, wearing sunglasses when full,
sweating when you are about to die at 4%.

**Why it is not just another battery percentage app**

| Commodity battery apps | Wattson |
| --- | --- |
| Static battery glyph | Live animated mascot with 9 moods |
| "73%" | 73% **+ real wattage flow** (measured on battery, estimated on AC) |
| A dropdown list | A dashboard: ring gauge, flow meter, 24 h sparkline, health panel |
| — | A running character overlay in a screen corner whose stride rate is your live power draw |
| — | Honest measurement confidence labels (`measured` / `estimated`) instead of fake precision |
| — | Energy accounting in Wh, session cost, adapter negotiation details |

**Target user:** Apple Silicon MacBook owners who care about runtime — developers,
video editors, students, people who travel with a 30 W charger and want to know if it
is actually keeping up.

---

## 2. Feature map

### Always free (the app must be genuinely useful without paying — App Store 3.1.2)
- Live power source (battery / adapter) + charge percentage
- Charge state: discharging, charging, charging paused, fully charged
- Live battery flow in watts and amps (measured)
- System draw estimate while plugged in
- Time-to-empty / time-to-full
- The mascot in the menu bar, with the default "Classic" skin and all moods
- The corner runner overlay with the default runner
- Basic battery health readout (cycle count, max capacity)

### Wattson Pro (subscription)
- **Skins**: 6 mascot skins + 5 runner characters (Retro, Neon, Pixel, Vaporwave, Ghost, Robot)
- **History**: 30-day power history, sparkline, per-session energy in Wh, discharge-rate trends
- **Smart alerts**: custom low/high thresholds, "unplugged and burning >30 W" alert,
  "charge limit reached", thermal alerts, quiet hours
- **Deep diagnostics**: adapter negotiation table, per-cell voltage where exposed,
  temperature history, raw IOKit inspector
- **Export**: CSV / JSON export of history
- **Menu bar customization**: choose exactly which figures ride in the menu bar
- **Runner playground**: speed multiplier, corner choice, size, confetti density

Pricing (configured in App Store Connect, mirrored in `App/Resources/Wattson.storekit`):
- Monthly `pro.monthly` — 7-day free trial
- Yearly `pro.yearly` — best value, 7-day free trial
- Lifetime `pro.lifetime` — non-consumable, for people who hate subscriptions

**No account. No login. No server.** Entitlement is derived purely from
`StoreKit.Transaction.currentEntitlements`, which Apple already ties to the user's
Apple Account and Family Sharing. This removes the entire class of auth bugs and the
entire class of privacy disclosures.

---

## 3. Architecture

```
┌──────────────────────────── App (AppKit + SwiftUI, macOS 13+) ────────────────────────────┐
│                                                                                            │
│  StatusItemController ── NSStatusItem ── MenuBarMascotView (SwiftUI, TimelineView)          │
│         │  click ▸ toggles dashboard popover / runner overlay                               │
│         ▼                                                                                   │
│  DashboardView ─ RingGauge · FlowMeter · Sparkline · HealthPanel · AdapterPanel             │
│  SettingsView · PaywallView                                                                 │
│  RunnerOverlayController ── borderless NSPanel pinned to a screen corner ── RunnerScene      │
│                                                                                            │
│  PowerMonitor (ObservableObject)                                                            │
│    ├── PowerReading source: IOKitPowerReader   (IOPowerSources + AppleSmartBattery)         │
│    ├── wake-ups: IOPSNotificationCreateRunLoopSource + adaptive timer                       │
│    └── publishes PowerSnapshot ▸ everything above                                           │
│                                                                                            │
│  StoreManager (StoreKit 2) · NotificationService · HistoryStore · PreferencesStore          │
└────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │ depends on
                                        ▼
┌──────────────────── WattsonCore (pure Swift, zero UI, zero IOKit, unit-tested) ────────────┐
│  PowerSnapshot · ChargeState · AdapterInfo · BatteryHealth                                  │
│  PowerMath          — watt arithmetic, draw estimation + confidence, runtime projection     │
│  SnapshotSmoother   — EMA de-jitter with state-change reset                                 │
│  PowerHistory       — bounded ring buffer, downsampling, Wh integration, stats              │
│  MascotMood         — deterministic snapshot ▸ mood mapping + dialogue                      │
│  AlertEngine        — threshold decisions with hysteresis + cooldown                        │
│  ProFeature         — the free/pro capability matrix                                        │
│  Formatters         — every user-facing string                                              │
│  Preferences        — Codable settings model with validated defaults                        │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

The split exists so that everything with a decision in it is testable on any machine with
`swift test`, while the untestable parts (IOKit, AppKit, StoreKit) stay thin and dumb.

---

## 4. How the numbers are obtained

| Value | Source | Confidence |
| --- | --- | --- |
| Percentage, source, time remaining | `IOPSCopyPowerSourcesInfo` (public, sandbox-safe) | measured |
| Voltage, amperage, capacity, cycles, temperature, adapter | `IORegistry` → `AppleSmartBattery` (public read-only registry access) | measured |
| Battery flow (W) | `V × I`, sign preserved (+ into battery, − out of battery) | measured |
| System draw **on battery** | `−(V × I)` — everything the machine burns comes out of the cell | **measured** |
| System draw **while charging** | `adapterInput − batteryChargePower` | **estimated** |
| System draw **when full / paused** | negotiated adapter power (battery flow ≈ 0) | **estimated** |

Wattson never dresses an estimate up as a measurement: every wattage figure carries a
confidence badge, and the "estimated" badge has a tooltip explaining exactly what the
math was. This is a deliberate product decision — it is the difference between a tool
an engineer trusts and a toy.

**No private API is used.** `IOReport`/`SMC` would give per-core CPU/GPU wattage, but
they are not public API and are a rejection risk under guideline 2.5.1, so they are
out. Everything Wattson reads is documented, public, and works inside the App Sandbox.

---

## 5. Delivery plan (what this repository contains)

1. **Core** — models, math, history, moods, alerts, entitlement matrix, formatters + unit tests
2. **Power layer** — resilient IOKit reader (every key optional, multi-key fallbacks, never crashes on a missing property), adaptive polling, power-source change notifications
3. **Menu bar** — status item hosting an animated SwiftUI mascot, left-click dashboard, right-click menu
4. **Dashboard** — gauges, flow meter, history sparkline, health, adapter, tech panel
5. **Runner overlay** — click the menu bar icon ▸ a character runs along the bottom-left or bottom-right of the screen at a stride rate proportional to live watts
6. **Monetization** — StoreKit 2 manager, paywall, restore, trial eligibility, entitlement gating
7. **System integration** — notifications, launch at login (`SMAppService`), CSV export
8. **Ship** — sandbox entitlements, privacy manifest, hardened runtime, App Store checklist

---

## 6. Production hardening rules applied throughout

- No `!` force-unwraps, no `try!`, no `as!` in shipping code paths
- Every IOKit property is optional and independently degradable — one missing key never
  blanks the UI
- All IOKit objects released on every exit path (`defer { IOObjectRelease(...) }`)
- Timers coalesce and back off when on battery; the overlay stops rendering when hidden
- The mascot animation is driven by `TimelineView(.animation)` so it pauses when occluded
- Purchases are verified with `VerificationResult` — unverified transactions never grant Pro
- Failure of any subsystem (StoreKit offline, notifications denied, history unwritable)
  degrades to a working free app, never to a crash
- No analytics, no network calls of our own, no data leaves the machine
