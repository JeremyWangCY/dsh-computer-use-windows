# dsh-pc-pilot

English | [中文](./README.zh.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![Node](https://img.shields.io/badge/node-%E2%89%A522.12-green)

A **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) host plugin** that gives the model a single `computer` tool to observe and operate the local Windows desktop: an indexed UIA accessibility tree, per-window screenshots, background synthetic-cursor input that never steals focus, and — when a task truly requires it — real SendInput mouse/keyboard control.

While acting, the model moves a small **codex-style on-screen cursor** (a rounded arrow with a soft blue radial glow) to each target point, so a human can follow exactly what the AI is about to click or type. The cursor is click-through, never takes focus, and auto-hides three seconds after the last action.

## Features

- **One tool, full desktop** — `list_apps`, `get_app_state`, `click_element`, `click`, `set_value`, `type`, `key`, `scroll`, `drag`, `open_app`.
- **Background-first input** — actions run via UIA action patterns (Invoke / Toggle / Selection / ExpandCollapse / RangeValue / Transform), then pixel hit-testing, then `WM_CHAR` / `WM_KEY` / `WM_MOUSEWHEEL` messages. The target window is not brought forward and the user's real mouse/keyboard are never hijacked.
- **Per-task dispatch** — `dispatch: "foreground"` (real SendInput) exists for the cases that genuinely need it (canvas clicks, unsupported drags, apps with no background path); the tool guidance keeps background as the default and asks the model to be explicit when it goes foreground.
- **Virtual-cursor indicator** — per-pixel-alpha layered window (`UpdateLayeredWindow` + `CreateDIBSection`): rounded white arrow with black outline over a soft blue radial glow. Click-through (`WS_EX_TRANSPARENT`), non-activating (`WS_EX_NOACTIVATE` + `SW_SHOWNOACTIVATE`), always-on-top. Auto-hides 3 s after the last action and reappears on the next one.
- **High-DPI accurate** — the overlay calls `SetProcessDPIAware` at startup and positions itself in physical pixels, matching the physical coordinates the helper reports from UIA. Correct placement at 100% / 125% / 150% scaling.
- **Window screenshots** — `PrintWindow`-based per-window capture saved as PNG, returned with `get_app_state { screenshot: true }`.
- **Zero setup** — no daemons, no drivers, no admin rights. Everything runs through the Windows PowerShell 5.1 helper that ships inside the package.

## Requirements

- Windows 10 or 11
- DeepSeek Harness (DSH) with the `dsh-pc-pilot` bundle loaded in the `web` profile
- PowerShell 5.1 (built into Windows) and Node.js ≥ 22.12 (shipped with DSH)

## Installation

### From the DSH plugin market

Once listed, search for *dsh-pc-pilot* in the market and click install.

### From a GitHub release

```powershell
pnpm add https://github.com/JeremyWangCY/PC-Pilot/releases/download/v0.1.0-beta.1/dsh-pc-pilot-0.1.0-beta.1.tgz
```

Run this inside the DSH profile (`~/.dsh/profiles/web`), then restart the host.

### From source

```powershell
git clone https://github.com/JeremyWangCY/PC-Pilot.git
cd dsh-pc-pilot
pnpm add ./dsh-pc-pilot
```

Or link it manually: add `"dsh-pc-pilot": "link:./vendor/dsh-pc-pilot"` to the profile's `package.json` dependencies, add the bundle to `dsh.profile.bundles`, run `pnpm install`, and restart the host.

## Usage

The plugin registers one global tool, `computer`. Typical flow:

1. `computer { action: "list_apps" }` — running apps with pids, window titles, hwnds and rects.
2. `computer { action: "get_app_state", app: "Notepad", screenshot: true }` — indexed accessibility tree (element index / role / name / value / automation_id / rect / invokable) plus a window screenshot.
3. Act on the state — `click_element { app, element }`, `set_value { app, element, value }`, `type { app, text }`, `key { app, key, modifiers }`, `scroll { app, x, y, amount, direction }`, `drag { app, from_x, from_y, to_x, to_y }`.
4. Refresh the state after every UI change; element indexes are only valid for the `get_app_state` that produced them.

### Key parameters

| Parameter | Default | Notes |
| --- | --- | --- |
| `dispatch` | `background` | UIA patterns + window messages; never steals focus. `foreground` uses real SendInput — pick it per task only when the user asked for real control or the essential action has no background path. |
| `overlay` | `true` | Show the click-through cursor at each action point; it auto-hides 3 s after the last action. |
| `screenshot` | `true` | Capture a per-window PNG in `get_app_state`. |
| `app` | — | pid number, process name, or window-title substring; `window_index` disambiguates multiple windows. |
| `x` / `y` | — | Window-local pixels (with `app`) or screen coordinates (without). |

## How it works

```
model ── computer tool ──> host (Node ESM bundle)
                              │  spawns PowerShell 5.1 helper per action (JSON in / JSON out)
                              ├─> UIA accessibility tree (IUIAutomation)
                              ├─> PrintWindow / CopyFromScreen screenshots
                              ├─> background input: UIA patterns → pixel hit-test → WM_* messages
                              ├─> foreground input: SendInput
                              └─> overlay: UpdateLayeredWindow per-pixel-alpha layered window
```

The helper is a single self-contained `computer-use-helper.ps1` copied to `%TEMP%` once per host start; the overlay is `virtual-cursor-overlay.ps1`, a resident low-frequency loop that reads a state file and blits a 48×48 DIB with `UpdateLayeredWindow`. Registration uses the harness tool API (`defineTool` + `ctx.tools.register`) with `isConcurrencySafe: false`, so desktop actions serialize.

## Security considerations

- The tool can read window titles, accessibility trees and screenshots, and can drive input into the user's applications. The bundled tool description instructs the model to operate **only** what the user explicitly asked for and to never submit forms, send messages, make purchases, delete data, or change account/settings without explicit instruction.
- Background actions never move the user's cursor or steal focus. Foreground actions do — the guidance requires the model to say so.
- No network access, no telemetry, no persistence beyond `%TEMP%\dsh-cua-*` state files.

## Troubleshooting

- **The cursor indicator does not appear** — check `%TEMP%\dsh-cua-diag.log` (boot diagnostics) and make sure the host was restarted after installation.
- **The indicator is visible but misplaced** — ensure the installed version calls `SetProcessDPIAware` (all ≥ 0.1.0 builds do); mismatched DPI awareness shifts the overlay by the scaling factor.
- **Desktop icons vanish / gray boxes appear** — this is a Windows shell (WorkerW) glitch typically caused by desktop-organizer or wallpaper tools, not by this plugin; restarting `explorer.exe` restores the desktop.
- **`background_unavailable`** — the target has no background path (canvas, some WinUI/Chromium surfaces). Decide per task whether to go `foreground`.

## Development

```powershell
git clone https://github.com/JeremyWangCY/PC-Pilot.git
cd dsh-pc-pilot
pwsh -File scripts/smoke-test.ps1
```

The smoke test exercises helper actions (`list_apps`, `get_app_state`, background clicks) against a real window. To run the plugin from a local checkout, link it into a DSH profile as shown above.

## License

[MIT](LICENSE)
