# Claude Multi Usage

A lightweight macOS menu-bar app that tracks the usage limits of **multiple**
Claude accounts side by side - the 5h session window, the 7-day window, and any
model-scoped weekly limits (e.g. Fable) - with reset-time and threshold
notifications.

The menu-bar label shows the peak utilization across all your accounts at a
glance, tinted orange/red as you approach the limit.

> [!NOTE]
> Not affiliated with Anthropic. This is an independent tool that reads your own
> account usage through the same OAuth API that Claude Code uses.

## Features

- **Multi-account** - track as many Claude accounts as you like, one row each.
- **All windows** - 5h session, 7-day, and model-scoped weekly limits, each with
  its own progress bar, percentage, and relative reset time.
- **Menu-bar label** - shows the highest utilization across all accounts; turns
  orange at 80% and red at 90%.
- **Notifications** - a local notification when a window resets, plus a warning
  when a window crosses 80% / 90%.
- **Rename accounts** - give each account a friendly name; its email stays
  visible so you always know which account is which.
- **Localized** - English, German, French, Italian, Spanish (follows your macOS
  system language).
- **Auto-refresh** - polls every 15 / 30 / 60 minutes (your choice) and refreshes
  when you open the menu if the data is stale.

## Privacy & how it works

Each account gets its **own independent OAuth session**. You log in once per
account through the browser (PKCE flow), and the app keeps its own refresh-token
chain in `~/.config/claude-multi-usage/accounts.json` (file mode `0600`).

- It does **not** read or touch Claude Code's keychain or tokens - no
  collision, no keychain password prompts, Claude Code stays untouched.
- Usage numbers are **never stored locally**. They are fetched live from
  `https://api.anthropic.com/api/oauth/usage`, one call per account per refresh
  interval. Reset times arrive in the same response.
- No telemetry, no third-party servers. The only network calls are the OAuth
  token endpoint and the usage endpoint, both at Anthropic.

## Requirements

- macOS 13 (Ventura) or later
- To build from source: a Swift 5.9+ toolchain (Xcode 15+ or the Swift command
  line tools)

## Install

### Download a release

Grab the latest `.zip` from the [Releases](../../releases) page, unzip it, and
move `ClaudeMultiUsage.app` to your Applications folder.

Releases built with a configured Developer ID are **signed and notarized** by
Apple and open normally. If a build is only **ad-hoc signed** (no Developer ID
configured), Gatekeeper will warn on first launch - either right-click the app
and choose **Open**, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/ClaudeMultiUsage.app
```

### Build from source

```sh
git clone https://github.com/schemann/claude-multi-usage.git
cd claude-multi-usage
make run
```

`make run` builds a release binary, assembles the `.app` bundle, codesigns it,
and launches it. Signing defaults to ad-hoc; to use your own Apple Developer
identity (recommended for a stable signature across rebuilds):

```sh
make run IDENTITY="Apple Development: Your Name (TEAMID)"
```

## Usage

1. Click the gauge icon in the menu bar.
2. Click **Add account** - the browser opens the Claude login.
3. Log in as the account you want, authorize, and copy the code shown.
4. Back in the app, click **Connect from clipboard** (or paste `code#state`
   manually and click **Connect**).
5. Repeat for each account. Hover a row for the rename (pencil) and remove
   (trash) buttons.

If a refresh token dies, the row shows "Expired - reconnect"; just add that
account again.

## Development

The app is a single SwiftPM executable target packaged into a signed `.app`
bundle (a proper bundle + bundle id is required because `UNUserNotificationCenter`
crashes otherwise; `LSUIElement` + the `.accessory` activation policy make it
menu-bar-only with no dock icon).

```
make build     # swift build -c release
make bundle    # build + assemble + codesign the .app
make run       # bundle + launch
make clean
```

Localized strings live in `Sources/ClaudeMultiUsage/Resources/<lang>.lproj/`.
To add a language, add a `<lang>.lproj/Localizable.strings` and list it in
`CFBundleLocalizations` in `Info.plist`.

## Acknowledgements

Descended from the ideas in
[Blimp-Labs/claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar),
re-architected for multiple accounts.

## License

[MIT](LICENSE) © Daniel Schemann
