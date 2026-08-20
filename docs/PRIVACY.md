# Privacy

Wattson's privacy story is short because the app is built so there is nothing to tell.

## What leaves your Mac

Nothing.

Wattson makes no network requests of its own. It has no analytics, no crash reporting
SDK, no remote configuration and no server component. The only network traffic
associated with the app is StoreKit talking to the App Store, which is handled by
macOS itself and never routed through app code.

## What is stored, and where

| Data | Where | Why |
| --- | --- | --- |
| Preferences | `UserDefaults`, in the app's sandbox container | To remember your settings |
| Power history (timestamp, charge %, watts, charge state) | `~/Library/Containers/com.navwireless.wattson/Data/Library/Application Support/Wattson/history.json` | To draw the history chart and compute trends |

History is capped in memory and pruned to your retention setting on every write, so
it cannot grow without bound. "Clear history" in Settings → Pro deletes it
immediately. Deleting the app removes the container and everything in it.

## Accounts

There are none. Wattson Pro is unlocked by `StoreKit.Transaction.currentEntitlements`,
which the App Store scopes to your Apple Account and to Family Sharing. The app never
sees your Apple Account details, never asks for an email address, and has no login of
any kind — which also means it has no password to leak and no session to hijack.

## What Wattson reads from the system

Two public, sandbox-permitted sources:

* `IOPowerSources` — charge level, power source, charging flags, time estimates.
* The `AppleSmartBattery` IORegistry node — voltage, current, capacities, cycle count,
  temperature, adapter description.

These describe the hardware, not you. Nothing is transmitted, and nothing is written
anywhere except the two locations in the table above.

## Notifications

Permission is requested lazily — the first time an alert actually needs to be
delivered, or when you switch alerts on in Settings. If you never cross a threshold,
you are never asked.
