# zbar

A macOS menu-bar companion for [zdx](https://github.com/tallesborges/zdx): ask a question, act on selected text, or open a throwaway session — from anywhere, without leaving the app you're in.

zbar is built with AppKit and Swift and runs as a menu-bar agent with no Dock icon and no windows. It never links zdx; the `zdx` CLI is the entire contract, invoked as a subprocess. Global shortcuts use Carbon hotkeys, which need no permissions, so asking questions works the moment you launch it.

## Features

- **Quick ask** — a floating panel for one-off questions, with follow-up turns that keep their context
- **Selection actions** — apply a preset prompt to the current selection in any app, preview the result, and replace it in place
- **Editable presets** — actions are Markdown files with frontmatter; drop one in and it appears
- **Model and reasoning switching** — pick either per conversation from a searchable list
- **Speech** — have any result read aloud
- **Throwaway sessions** — open a full interactive zdx session in a fresh temporary directory

## Requirements

- macOS 14 or later
- [`zdx`](https://github.com/tallesborges/zdx) on your login shell `PATH`
- Xcode command-line tools (`swift`, `codesign`)
- Optional: [`zmux`](https://github.com/tallesborges/zmux) — sessions open there when available, otherwise in whichever terminal owns the `.command` file association

## Build & run

```sh
./build-app.sh          # builds build/zbar.app
open build/zbar.app
```

`build-app.sh` recreates only `build/zbar.app/Contents`, never the bundle directory itself, and signs with a stable Apple Development identity when one exists (override with `ZBAR_CODESIGN_IDENTITY`). Both matter: macOS resolves permission grants through the bundle's inode and code signature, so replacing either makes it re-prompt on every build.

## Shortcuts

Global, and configurable:

| Shortcut | Action |
| --- | --- |
| `⌃⌥Space` | Quick ask |
| `⌃⌥A` | Selection actions |

In the panel:

| Shortcut | Action |
| --- | --- |
| `⏎` | Ask, or follow up on the current conversation |
| `⌘⏎` | Open a full session in a fresh temporary directory |
| `⇧⌘M` | Change model |
| `⇧⌘T` | Change reasoning level |
| `⌘C` | Copy the latest answer |
| `⌘S` | Speak the latest answer, or stop |
| `⎋` | Close |

In a picker: `↑` `↓` to move, `⏎` to choose, `⎋` to cancel. Short lists also accept `1`–`9`; the model picker filters as you type instead.

## Configuration

Both live under `$ZDX_HOME/zbar` and are seeded on first run. The menu bar has items to open them.

### Settings — `config.md`

```markdown
---
quick_ask: ctrl+opt+space
selection_actions: ctrl+opt+a

# model: claude-cli:claude-opus-5@medium
# thinking: medium
tools: true
---
```

Shortcut modifiers are `ctrl`, `opt`, `cmd` and `shift`; keys are `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`, `comma`, `period` and `slash`.

`model` is a zdx model spec, `provider:model[@thinking][@fast]`. `tools` gives quick ask the full agent — skills, memory and file access — at the cost of speed; set it to `false` for plain, faster answers.

`model`, `thinking` and `tools` are re-read every time a panel opens. Shortcut changes need a relaunch.

### Actions — `actions/*.md`

One file per selection action, mirroring how zdx describes subagents. Only the body is required.

```markdown
---
name: Prof-read
description: Fix grammar and spelling, keep the meaning
replaces: true
# model: openai:gpt-5-mini@low
---
Proofread the text below. Reply with the corrected text only.
```

The selected text is appended under a `TEXT:` heading. `replaces: false` shows the result without offering to overwrite the selection — right for explain-style actions. Filenames order the picker, so a numeric prefix keeps the number keys stable. The directory is re-read every time the picker opens.

## Permissions

- **Accessibility** is required for selection actions only, to read the selected text and paste a replacement back. Quick ask works without it.
- **Full Disk Access** is optional but recommended once `tools` is on. macOS treats access to other apps' data as a transient, per-process privilege, so it re-prompts for every question otherwise.

zbar reads the selection through the Accessibility API where an app supports it, and falls back to a synthetic `⌘C`. The pasteboard is snapshotted with every item and type and restored afterwards, and a replacement is only pasted once the original app is confirmed frontmost again.
