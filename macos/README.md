# Claude Code Quota — macOS menu-bar app

The macOS sibling of the [KDE Plasma widget](../README.md). Puts your Claude
Code subscription usage in the menu bar: a small color-coded pill showing your
5-hour-block %, green → amber → red as you approach the cap. Click it for the
full breakdown.

It shares the Linux port's design and the **same calibration logic** — only the
view layer (a native Swift status-bar app instead of a QML plasmoid) and the
scheduler (a `launchd` agent instead of a systemd timer) differ.

## Why this exists

Claude Code's built-in `/usage` only works inside an interactive session. This
app reads the same local transcripts Claude Code writes (via
[ccusage](https://github.com/ryoppippi/ccusage)) and surfaces a calibrated
approximation in your menu bar — a "is now a good time to start a long Opus
session?" indicator you can glance at from anywhere.

## What you see

In the menu bar (always visible):

- A small color-coded pill showing your **5-hour block %**
- Green ≤ 60 %, amber 60–85 %, red > 85 %
- Hover for a tooltip: `Claude Code: 5h 18% · wk 6%`

Click the pill for the popover:

- **5-hour block** — progress bar, % used, resets-in, API-equivalent cost
- **Weekly** — progress bar, % used, resets-in, API-equivalent cost
- Last-refresh timestamp, plus **Refresh** and **Quit** buttons

## How it works

Three pieces, intentionally separated — the same shape as the Linux port:

```
┌────────────────────────────────┐
│ 1. claude-quota-fetch          │ bash + jq + ccusage (BSD date)
│    runs every 5 min via        │     ↓ writes
│    a launchd LaunchAgent        │ ~/Library/Caches/claude-quota/state.json
└────────────────────────────────┘            ↑ reads
                                              │ (every 10s)
┌────────────────────────────────┐            │
│ 2. ClaudeQuota.app (Swift)     │────────────┘
│    NSStatusItem pill + popover │
└────────────────────────────────┘
```

The **launchd agent enforces the 5-minute refresh floor** (`StartInterval=300`)
— Anthropic's API issues abuse warnings if you poll the underlying data too
aggressively, so the agent is the single source of truth for cadence. The app is
a pure view: it reads the cache file every 10 s and renders the pill.

## How the percentage is computed (and why it's cost, not tokens)

The percentage basis is **API-equivalent cost**, not raw token count. ccusage's
token totals are ~90–97 % *cache-read* tokens, which Anthropic's limits weight at
roughly 0.1×. Dividing raw tokens by a token cap therefore over-reports
several-fold — and inconsistently, because the cache-read fraction differs
between the 5-hour and weekly windows (this is the bug that made an early version
read 66 % when `/usage` said 7 %).

Cost already encodes Anthropic's weighting (cache-read 0.1×, output 5×, Opus 5×
over Sonnet), so **cost ÷ cost-cap tracks `/usage` far more closely** — typically
within a point or two on the weekly window. It still won't match exactly:
ccusage reads local JSONL while `/usage` reads Anthropic's own API, and the
5-hour *rolling* block doesn't align with `/usage`'s fixed-reset session window.

The dollar figures are **API-equivalent** cost — what your token volume *would*
cost at public pay-per-token list prices — not your subscription billing and not
a real spend. Cache-read-heavy coding (often 90–97 % of tokens) inflates this
figure ~10×, so a heavy week can read as hundreds of API-equivalent dollars.

> **The `*_CAP_USD` values are calibration denominators, not budgets.** A
> `WEEKLY_CAP_USD` of 9000 does **not** mean Anthropic grants you $9,000/week —
> it's just the API-equivalent figure that corresponds to 100 % of your limit
> (`your $-at-7% ÷ 0.07`). It exists only to turn cost into a percentage; the
> popover shows the **% of limit** (the trustworthy number) and the
> API-equivalent **$ spent**, never a "$X of $Y" ceiling.

## Prerequisites

- **macOS 13+** (built and tested on macOS 26 / Apple silicon).
- **Xcode command-line tools** (`swift` — `xcode-select --install`).
- **`jq`** for JSON normalization (`brew install jq`).
- **Node.js** (`npm`/`npx`) to install `ccusage`. The installer runs
  `npm i -g ccusage` for you; if you already have `ccusage` on `PATH` it's used
  directly. Pass `--no-ccusage` to fall back to `npx -y ccusage@latest` at every
  fire (~6 s slower per refresh).

## Install

```sh
cd macos
./install.sh
```

Or with [just](https://github.com/casey/just):

```sh
just install
```

This builds `Claude Quota.app` into `~/Applications`, installs the fetch script
and launchd agent, primes the cache with one run, and launches the app. Look for
the colored % pill in your menu bar.

To launch at login: **System Settings → General → Login Items → +** and add
**Claude Quota**.

## Tuning the caps

`/usage` knows your authoritative ceilings; this app only sees local cost. Right
after install, run `/usage` once and set each USD cap in
`~/.config/claude-quota/limits.env` to **the popover's "$ used" ÷ the `/usage`
percentage**, then reload the agent:

```sh
# e.g. popover shows "$642" on the weekly bar and /usage says 7% →
#   WEEKLY_CAP_USD = 642 / 0.07 ≈ 9000
$EDITOR ~/.config/claude-quota/limits.env
launchctl kickstart -k gui/$(id -u)/io.github.fuziontech.claude-quota
```

Rough starting points (eyeballed against `/usage` on Max 20x — your mileage will
vary with how cache-heavy your sessions are):

| Plan | `FIVE_HOUR_CAP_USD` | `WEEKLY_CAP_USD` |
|---|---|---|
| Pro | 12 | 600 |
| Max 5x | 40 | 2,300 |
| Max 20x | 150 | 9,000 |

## Development

```sh
just build      # compile the release binary
just app        # assemble Claude Quota.app under build/
just run        # run the just-built binary in the foreground (logs to terminal)
just reload     # rebuild + reinstall + relaunch after editing Swift sources
just refresh    # force one fetch cycle now and print state.json
just status     # launchd agent state + last exit code
just logs       # tail the fetch agent logs
just lint       # shellcheck the bash scripts
```

The app is a Swift Package (no Xcode project): `swift build` produces the
binary, `make-app.sh` wraps it in a `.app` bundle with an `LSUIElement` Info.plist
(menu-bar agent, no Dock icon).

## Troubleshooting

- **Pill shows `…`** — the cache file hasn't been written yet. Run
  `just refresh`; the first `ccusage` run can take a few seconds to cold-start.
- **Pill shows `!`** — the app can't read `state.json`. Check the fetch agent:
  `cat /tmp/claude-quota.err.log`.
- **No pill at all** — confirm the app is running (`pgrep -lf ClaudeQuota`); if
  not, `open "~/Applications/Claude Quota.app"`.
- **Percentages way off from `/usage`** — your caps need calibration (see above).

## Uninstall

```sh
just uninstall   # remove app, agent, fetch script (keeps limits.env)
just purge       # also remove ~/.config/claude-quota and the cache
```

## License

MIT. See [../LICENSE](../LICENSE).
