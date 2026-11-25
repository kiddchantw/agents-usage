# Agents Usage Menu Bar App

**English** | [繁體中文](README.zh-TW.md)

A small macOS menu bar app that shows your **Claude** and **Codex** usage — the **session (5-hour)** and **weekly** limits — in one place, so you no longer have to open each service's usage page.

> **Unofficial tool, not affiliated with Anthropic or OpenAI.** It relies on undocumented interfaces and may stop working at any time. Use at your own risk. See [Privacy and risks](docs/privacy-and-risks.md) (in Chinese).

![Agents Usage panel screenshot](docs/screenshot.png)

## Reading the screen

The **menu bar** (top right) shows two lines and four numbers:

```
A  21/  5 %      ← Claude: 5-hour / weekly
O   8/ 14 %      ← Codex:  5-hour / weekly
```

**Click it** to open the panel. Claude and Codex each get a section, with one row per limit:

| Column | Meaning |
| --- | --- |
| Name | For example `Current session`, `Weekly · All models`, `5-hour limit` |
| `Used` | The percentage **already used** in this window (not what is left). Orange from 50%, red from 80% |
| `Resets` | When the window resets, such as `Today 16:10` or `Tue 16:00`. Hover to see the time remaining |

The **thin marker** on each progress bar shows how much of the window has already elapsed. If the filled part of the bar is past the marker, you are using your quota faster than time is passing.

Bottom left, `↻` refreshes manually and the text next to it is the last update time. `Quit` is at the bottom right. The app has no Dock icon and lives only in the menu bar.

## Requirements

- macOS 13 (Ventura) or later, and the Xcode command line tools (`xcode-select --install`)
- **Claude Code** and **Codex CLI** installed and signed in (Codex with a ChatGPT account). They are independent: with only one installed, the other section simply shows an error
- A paid plan that has per-window limits

## Quick start

```bash
bash build.sh
open AgentsUsage.app
```

On first launch, macOS asks whether to allow access to Claude Code's credentials. Choose **Always Allow**.

## More

The pages below are currently in Chinese only.

- [Installation details](docs/install.md): launch at login, uninstall
- [How it works](docs/how-it-works.md): how Claude and Codex usage is read, refresh interval, technical notes
- [Troubleshooting](docs/troubleshooting.md)
- [Privacy and risks](docs/privacy-and-risks.md)
