# Claude Multi Usage - project context

macOS menu-bar app that tracks the 5h/7d usage limits of **multiple** Claude
accounts at once, with reset-time and threshold notifications. Standalone;
descended from the ideas in `Blimp-Labs/claude-usage-bar` but re-architected for
multi-account.

## Key design decisions (why it is built this way)

- **Own OAuth session per account, NOT Claude Code's keychain tokens.**
  An earlier prototype read Claude Code's tokens straight out of the macOS
  keychain (`Claude Code-credentials` for `~/.claude`, `Claude Code-credentials-<sha256(dirpath)[0..8]>`
  for `~/.claude-<name>`). Dropped because:
  1. Refresh tokens **rotate** server-side - self-refreshing would invalidate
     Claude Code's own token and log it out.
  2. Reading another app's keychain item triggers macOS permission prompts.
  Instead: each account does its own OAuth PKCE login once; we keep our own
  refresh-token chain in `~/.config/claude-multi-usage/accounts.json` (0600).
  Zero interaction with Claude Code, no keychain prompts.

- **Usage numbers are not stored locally.** They only come from
  `https://api.anthropic.com/api/oauth/usage` (one call per account per refresh
  interval). Reset times (`resets_at`) arrive in the same response.

- **OAuth client** is the public Claude Code client id
  `9d1c250a-e61b-44d9-88ed-5944d1962f5e`; token endpoint
  `https://platform.claude.com/v1/oauth/token`; fixed redirect
  `https://platform.claude.com/oauth/code/callback` (so the code is copy-pasted
  back manually - the app reads it from the clipboard).

## Build / run

`make run` = `swift build -c release` -> assemble `.app` bundle -> codesign ->
launch. The codesigning identity is the `IDENTITY` variable in the `Makefile`;
it defaults to ad-hoc (`-`). For local development, override it with your own
stable identity (e.g. `make run IDENTITY="Apple Development: ..."` or export it)
so the code signature stays constant across rebuilds.

Requires: proper `.app` bundle + bundle id (`dev.schemann.claude-multi-usage`)
because `UNUserNotificationCenter` crashes outside a bundle; `LSUIElement`
+ `.accessory` activation policy = menu-bar-only, no dock icon.

## Features

- One row per account: 5h + 7d progress bars, % and reset time.
- Menu-bar label shows the peak utilization across all accounts.
- Reset notifications: local notification scheduled at each window's reset time.
- Threshold warnings: notification when a window crosses 80% / 90%
  (`AppModel.warnThresholds`), deduped per window instance.
- Add account (browser login + clipboard connect) / remove account (hover row).

## Conventions

- No em/en-dashes anywhere (ASCII hyphen only).
- German UI copy uses "du".
