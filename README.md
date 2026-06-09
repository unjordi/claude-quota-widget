# Claude Code Quota Widget

A KDE Plasma 6 widget for Linux that puts your Claude Code subscription usage in your panel. Color-coded pill that turns green → amber → red as you approach the cap; click for the full breakdown.

![Panel pill + popup](screenshots/panel-and-popup.png)

## Why this exists

Claude Code's built-in `/usage` command only works inside an interactive Claude Code session. If you want to glance at your 5-hour-block and weekly utilization from anywhere on your desktop — without launching a Claude prompt and typing a slash command — there's no native way to do it.

This widget reads the same local transcripts Claude Code writes (via [ccusage](https://github.com/ryoppippi/ccusage)) and surfaces a calibrated approximation in your panel. It's a "is now a good time to start a long Opus session?" indicator.

## What you see

Compact (always visible in the panel):

- A small color-coded pill showing your **5-hour block %**
- Green ≤ 60 %, amber 60–85 %, red > 85 %

Popup (click the pill):

![Popup](screenshots/popup.png)

- 5-hour block — progress bar, % used, resets-in, API-equivalent cost
- Weekly — progress bar, % used, resets-in, API-equivalent cost
- Last-refresh timestamp

Hover gives a one-line tooltip: `Claude Code: 5h 18% · wk 6%`.

## How it works

Three pieces, intentionally separated:

```
┌────────────────────────────────┐
│ 1. claude-quota-fetch          │ bash + jq + ccusage
│    runs every 5 min via        │     ↓ writes
│    systemd --user timer        │ ~/.cache/claude-quota/state.json
└────────────────────────────────┘            ↑ reads
                                              │ (every 10s)
┌────────────────────────────────┐            │
│ 2. plasmoid (QML, Plasma 6)    │────────────┘
│    panel pill + popup + tip    │
└────────────────────────────────┘
```

The **systemd timer enforces the 5-minute refresh floor** at the kernel level — Anthropic's API issues abuse warnings if you poll the underlying data too aggressively, so the timer is the single source of truth for cadence (`OnUnitActiveSec=5min`, `Persistent=true`). The plasmoid is a pure view: it reads the cache file every 10 s and renders.

## ⚠ The percentages are approximations

ccusage parses local JSONL transcripts and multiplies by Anthropic's published per-model token rates. `/usage` reads Anthropic's own usage API. They will **not** match exactly — typically within a few percentage points for the 5-hour block and within ~10 % for the week.

The dollar values shown in the popup are **API-equivalent** cost (what you'd have paid on pay-per-token), not your subscription billing. They're a "how much is my subscription saving me?" signal, not an invoice.

Calibrate the caps in `~/.config/claude-quota/limits.env` against your own `/usage` reading on day one. See the **Tuning the caps** section below.

## Prerequisites

- **KDE Plasma 6** (Fedora 41+ / Kubuntu 24.04+ / Arch / others).
- **`jq`** for JSON normalization.
- **`npm`** to install `ccusage` (the installer runs `npm i -g ccusage` for you). If you already have `ccusage` on `PATH`, that's used directly. If neither is present, pass `--no-ccusage` to fall back to `npx -y ccusage@latest` at every fire (~7 s slower per refresh).

## Install

```sh
git clone https://github.com/fuziontech/claude-quota-widget
cd claude-quota-widget
./install.sh
```

Or with [just](https://github.com/casey/just):

```sh
just install
```

Then in Plasma: right-click your panel → **Add or Manage Widgets…** → search **"Claude Code Quota"** → drag it onto the panel.

## Tuning the caps

`/usage` knows your authoritative ceilings; this widget only sees tokens. Right after install, run `/usage` once and edit the caps in `~/.config/claude-quota/limits.env` so the widget's percentages roughly match:

```sh
$EDITOR ~/.config/claude-quota/limits.env
systemctl --user restart claude-quota.service
```

Starting points calibrated against `/usage` on the user's plan:

| Plan | `FIVE_HOUR_CAP_TOKENS` | `WEEKLY_CAP_TOKENS` |
|---|---|---|
| Pro | 50,000,000 | 200,000,000 |
| Max 5x | 200,000,000 | 600,000,000 |
| Max 20x | 400,000,000 | 1,200,000,000 |

## Troubleshooting

```sh
just status   # is the timer running? what was the last fetch?
just logs     # follow the fetch service journal
just refresh  # force a fetch right now and print the result
```

Common gotchas:

- **Pill stays gray with `…` text** — the cache file hasn't been written yet. Check `just status`; the first fetch can take a few seconds while `ccusage` cold-starts.
- **`error: cat rc=1`** — the fetch script crashed; check `journalctl --user -u claude-quota.service`. Usually a missing `jq` or `ccusage`.
- **Percentages way off from `/usage`** — your caps need calibration. See above.
- **Widget appears blank in the panel** — if you're seeing nothing at all (not even the colored pill), restart plasmashell once with `just reload-plasmashell`.

## Development

```sh
just upgrade-plasmoid    # rebuild + reinstall the plasmoid after editing main.qml
just reload-plasmashell  # restart plasmashell to pick up changes
just preview             # run the plasmoid standalone for visual debugging
just lint                # shellcheck the bash scripts
just package             # build dist/claude-quota-widget-X.Y.Z.plasmoid
```

## Uninstall

```sh
just uninstall              # remove everything
just uninstall-keep-cfg     # keep ~/.config/claude-quota/limits.env
```

## License

MIT. See [LICENSE](LICENSE).
