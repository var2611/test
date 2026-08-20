# App Store submission checklist

Everything below is either already true of the code in this repository, or is a step
that has to happen in App Store Connect / Xcode before the first submission.

## 1. Identifiers and products

- [ ] App ID `com.navwireless.wattson` registered (change the prefix in `project.yml`
      and `App/Store/StoreManager.swift` if you use a different one — the two must match).
- [ ] Subscription group **Wattson Pro** created, containing:
      - `com.navwireless.wattson.pro.monthly` — auto-renewable, 1 month, 1 week free trial
      - `com.navwireless.wattson.pro.yearly` — auto-renewable, 1 year, 1 week free trial
- [ ] Non-consumable `com.navwireless.wattson.pro.lifetime`.
- [ ] All three marked **Family Shareable** (the code already honours family entitlements).
- [ ] Localised display names and descriptions filled in — `Product.displayName` and
      `displayPrice` are what the paywall shows, so blank metadata means a blank paywall.

## 2. Signing and capabilities

- [x] App Sandbox enabled (`App/Resources/Wattson.entitlements`).
- [x] Hardened runtime on for Debug and Release (`project.yml`).
- [x] `com.apple.security.network.client` — required for StoreKit.
- [x] `com.apple.security.files.user-selected.read-write` — only used via `NSSavePanel`
      for the Pro history export.
- [x] No other entitlements requested. No temporary exceptions.
- [ ] `DEVELOPMENT_TEAM` set in `project.yml`.

## 3. Privacy

- [x] `PrivacyInfo.xcprivacy` present, declaring no tracking, no collected data, and
      the `UserDefaults` API reason `CA92.1`.
- [x] No analytics SDK, no crash reporter, no network calls of the app's own.
- [ ] App Privacy answers in App Store Connect set to **Data Not Collected**.
- [ ] Privacy policy URL live (the paywall links to `https://wattson.app/privacy` —
      change it in `App/UI/PaywallView.swift` to your real URL).

## 4. Guideline 3.1.2 — subscriptions

The paywall (`App/UI/PaywallView.swift`) already shows, above the buy button:

- [x] Subscription name and length of each period.
- [x] Price per period, taken from StoreKit rather than hard-coded.
- [x] Introductory offer terms, only when the account is actually eligible.
- [x] "renews automatically" and how to cancel.
- [x] Links to Terms of Use (Apple's standard EULA) and to the privacy policy.
- [x] **Restore Purchases**, reachable from the paywall *and* from Settings → Pro.

Also verified:

- [x] The free tier is a working app, not a demo (`EntitlementMatrix.freeTierPromise`
      is the list, and it is shown on the paywall so nobody buys something they have).
- [x] Nothing is gated behind an account, because there are no accounts.

## 5. Review notes to include with the build

> Wattson is a menu bar app — after launch, look for the battery character in the
> menu bar, not in the Dock. Click it to open the dashboard and to send the runner
> across the bottom corner of the screen.
>
> All power data comes from public APIs (`IOPowerSources` and the `AppleSmartBattery`
> IORegistry node). No private frameworks are used.
>
> To exercise the paid features without a purchase, run the app and use the
> "Restore purchases" flow with a sandbox account entitled to `…pro.yearly`, or
> build the Debug configuration where `StoreManager.debugForcePro` is available.

## 6. Before archiving

- [ ] Detach `Wattson.storekit` from the scheme (a StoreKit configuration file left
      attached makes purchases fake, and the reviewer will see no products).
- [ ] `make icon` has been run and the ten PNGs exist in the asset catalog.
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped in `project.yml`.
- [ ] `swift test` passes.
- [ ] Ran on a real machine on battery, on the adapter, at 100%, and with
      Low Power Mode on; then again on an Intel Mac if you support one.
- [ ] Checked Activity Monitor → Energy: Wattson should sit at negligible impact when
      the dashboard and the runner are both closed.

## 7. Screenshots

macOS App Store wants 1280×800 or 2560×1600. Worth capturing:

1. The menu bar mascot mid-charge with the dashboard open.
2. The runner overlay at the bottom-right with a high draw.
3. The history card over 24 h.
4. Settings → Appearance with the skin strip.
