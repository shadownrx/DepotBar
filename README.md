<p align="center">
  <img src="assets/logo.png" width="140" alt="DepotBar logo">
</p>

<h1 align="center">DepotBar</h1>

<p align="center">
  <strong>Your Depot CI, one click away.</strong><br>
  A macOS menu bar app that shows your latest Depot workflows — no more keeping the dashboard open.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/Depot-CI-ff6b35" alt="Depot CI">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license">
</p>

---

## What it looks like

Click the menu bar icon, get the state of CI:

```
Depot CI
------------------------------
✓  Tests & Deploy — macch-core · @octocat · 15m ago · 8m16s
✓  React Doctor — macch-core · @octocat · #317 · 15m ago · 31s
⠋  Test Docker Build — macch-hub · #42 · 1m ago · 1m10s
✓  Run MFA Tests — macch-hub · 3m ago · 4m02s
✗  Nightly E2E — macch-hub · 2h ago · 22m45s
------------------------------
Updated just now
Refresh now                  ⌘R
Open Depot dashboard         ⌘D
Set API Token…
Launch at Login              ✓
------------------------------
Quit DepotBar                ⌘Q
```

Click any workflow to open it on depot.dev. The menu bar icon itself tells the story at a glance:

| Icon | Meaning |
| ---- | ------- |
| animated spinner | a workflow is still running (or a refresh is taking >2s) |
| ✓ green check | everything finished clean |
| ✗ red cross | something failed |
| ⚠ triangle | couldn't reach Depot (see logs) |

## Features

- 📊 **Latest 5 workflows** with status, repo, author, PR number, age, and duration
- 🌀 **Live spinner** in the menu bar and on running rows
- 🔗 **One click** to open any workflow (or the whole dashboard) in your browser
- 🔄 **Auto-refresh** every 30 seconds, plus every time you open the menu
- 🚀 **Launch at login**, with a menu toggle
- 🔑 **Zero token setup** — reuses your Depot CLI login
- 🎟️ **API token option** — paste a Depot API token once (stored in your Keychain); falls back to your Depot CLI login when no token is set
- 👤 **Commit author in each row** — resolved from GitHub via your `gh` login (`@login`, or the raw commit name when unlinked); rows simply omit it when `gh` is missing or offline
- 🪶 **Native & tiny** — Swift + AppKit, no dependencies, no Electron

## Install

### Option A — Download (easiest)

1. Get `DepotBar.zip` from the [latest release](https://github.com/facmartoni/DepotBar/releases/latest).
2. Unzip and move `DepotBar.app` to `/Applications`.
3. First launch: right-click → **Open** (the app is ad-hoc signed, so Gatekeeper asks once), then confirm.

### Option B — Build from source

```sh
git clone https://github.com/facmartoni/DepotBar.git
cd DepotBar
./scripts/build-app.sh   # builds, installs to /Applications, launches
```

Requirements: macOS 14+, Xcode command line tools (`xcode-select --install`),
and the Depot CLI installed:

```sh
brew install depot/tap/depot
```

Without Homebrew, use the installer script instead (pick a dir on your PATH):

```sh
curl -fsSL https://depot.dev/install-cli.sh | DEPOT_INSTALL_DIR="$HOME/.local/bin" sh
```

Optional, for author names in each row:

```sh
brew install gh && gh auth login
```

## How auth works

DepotBar shells out to `depot ci workflow list -n 5 -o json`. Auth resolves
in this order:

1. `DEPOT_TOKEN` env var, when set.
2. The API token saved via the menu (**Set API Token…**, stored in your
   Keychain). Create one in your Depot Organization Settings → API Tokens.
3. Otherwise the CLI's own login (`depot login`) — the previous behavior.

So `depot login` is only needed when you use neither of the token options.
The org for web links is read from the CLI's own settings
(`DEPOT_ORG_ID` overrides it).

## Configuration

| What | How |
| ---- | --- |
| API token | Menu → **Set API Token…** (Keychain), or `DEPOT_TOKEN` env var |
| Org for links | `DEPOT_ORG_ID` env var, else the CLI's current org |
| Logs | `/tmp/depotbar.log` |
| Debug the menu without UI | `/Applications/DepotBar.app/Contents/MacOS/DepotBar --dump-menu` |
| Verify menu-open timers | `/Applications/DepotBar.app/Contents/MacOS/DepotBar --self-test` |
| Refresh interval / row count | constants in [`main.swift`](Sources/DepotBar/main.swift) / [`DepotClient.swift`](Sources/DepotBar/DepotClient.swift) — edit & rebuild |
| Theme | `theme` in `~/.config/depotbar/config.json`, or `DEPOTBAR_THEME` env var (wins) |

## Themes

`system` (default) follows macOS. `black` forces a fully dark menu —
black chrome, white text — no matter the system appearance. `glass` is
`black` plus a frosted-capsule menu-bar icon:

```jsonc
// ~/.config/depotbar/config.json
{ "theme": "black" }   // "system" | "black" | "glass"
```

No config file needed: DepotBar works out of the box and ignores unknown
theme names. A change applies the next time you open the menu (no relaunch).

## Project layout

```
DepotBar/
├── Sources/DepotBar/
│   ├── main.swift            # menu bar app: status item, menu, timers
│   ├── Config.swift          # ~/.config/depotbar/config.json + themes
│   ├── StatusIconArt.swift   # frosted-capsule icon (glass theme)
│   ├── DepotClient.swift     # Depot CLI wrapper + workflow models
│   ├── TokenStore.swift      # API token: Keychain storage + auth precedence
│   └── MenuPresentation.swift# menu strings + --dump-menu debug mode
├── Tests/DepotBarTests/
│   └── TokenAuthTests.swift  # token precedence + child-process env
├── Resources/
│   ├── Info.plist            # LSUIElement (menu-bar-only) bundle config
│   └── AppIcon.icns
├── assets/                   # logo.svg, logo.png, AppIcon.iconset
└── scripts/build-app.sh      # release build → .app bundle → /Applications
```

## Uninstall

```sh
pkill -x DepotBar
rm -rf /Applications/DepotBar.app
```

(DepotBar also unregisters its login item when you toggle it off in the menu
before quitting.)

## FAQ

**The icon doesn't appear after install.**
DepotBar is menu-bar-only (no Dock icon). Look at the right side of the menu
bar for the ✓/✗ icon. If it's really missing, check `/tmp/depotbar.log`.

**It says the Depot CLI was not found.**
Install it (`brew install depot/tap/depot`), then relaunch DepotBar. The CLI
binary is still required — the token only replaces `depot login`.

**Do I still need `depot login`?**
Only if you don't set a token. Either paste an API token via
**Set API Token…** or export `DEPOT_TOKEN`; both take precedence over the
CLI login.

**macOS says the app is from an unidentified developer.**
Right-click `DepotBar.app` → Open → Open. Only needed once (ad-hoc signature).

## Acknowledgments

Inspired by [DeployBar](https://deploybar.app) — same itch, but for
[Depot](https://depot.dev) CI. Not affiliated with Depot.

## License

[MIT](LICENSE) © 2026 Facundo García Martoni
