# Grok Plan Switcher

A macOS app for viewing the remaining shared Grok usage pool for two Grok Build logins and opening the CLI under the selected login.

## Install

Download the latest `.dmg` from [Releases](https://github.com/lalalaoneplus-dev/grok-plan-switcher/releases/latest), open it, and drag Grok Plan Switcher to Applications.

The custom Grok-and-switch icon is in `Resources/AppIcon.svg` (PNG preview: `Resources/AppIcon.png`). The app build renders it into the bundle's `.icns` icon.

## First use

1. Open `dist/Grok Plan Switcher.app`.
2. For each plan, choose **Sign in** and complete the corresponding xAI login in Terminal.
3. Return to the app and click **Refresh** to load each plan's remaining usage.
4. Choose a project folder, then click **Use Plan 1** or **Use Plan 2** to open Grok Build in Terminal. The app refreshes both quotas first and uses the other connected plan if the selected one is exhausted.

Failover applies to the next CLI launch. An active Grok session stays on its current account and must be restarted manually after it hits the limit.

Plan 1 uses the existing `~/.grok` login. Plan 2 has its own login in `~/.grok-plan2`.

## Build and run

```sh
./script/build_and_run.sh
```

Run `./script/package.sh` to build a universal release DMG in `dist/`.

The usage display reads each profile's existing Grok CLI login and sends a read-only billing request to xAI. It mirrors the internal endpoint used by Grok Build's usage screen; xAI may change that endpoint without notice. Tokens are kept in memory for the request and are not written to app logs or sent to another host.
