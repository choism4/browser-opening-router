# Browser Opening Router

A tiny (~95 KB), zero-RAM, open-source macOS default browser router written in pure Swift.

No menu bar icon. No background daemon. No subscription or paid license. It only launches when macOS opens a link, forwards the URL to the matching browser, and exits immediately.

## Why?

If you only need to route specific domains (like work tools, Claude, Google Meet, etc.) to a different browser without paying for a full-featured browser picker or keeping a resident app running, `BrowserOpeningRouter.app` does just that in ~140 lines of Swift with zero third-party dependencies.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`swiftc`)

## Install

```sh
git clone https://github.com/choism4/browser-opening-router.git
cd browser-opening-router
./scripts/install.sh
```

This compiles `Sources/main.swift`, ad-hoc signs the bundle, installs `/Applications/BrowserOpeningRouter.app`, and registers it with LaunchServices.

## Configure & Set as Default Browser

Open **Browser Opening Router** from `/Applications` (or Spotlight):

1. Click **Set as Default** to switch macOS's default web browser in one click.
2. Pick your **Default Browser** from the auto-detected list of installed browsers.
3. Click **+ Add Rule**, type comma-separated domains or URL prefixes (e.g. `claude.ai, claude.com`), and pick the target browser.
4. Test any URL right inside the window with **Test Open** — changes auto-save to `~/.config/browser-opening-router/config.json`, and closing the window exits completely (0 MB idle RAM).

You can also edit `~/.config/browser-opening-router/config.json` directly (see [config.example.json](config.example.json)):

```json
{
  "default_browser": "Safari",
  "rules": [
    {
      "browser": "Firefox",
      "domains": ["claude.ai", "claude.com", "anthropic.com"]
    },
    {
      "browser": "Google Chrome",
      "url_prefixes": ["https://meet.google.com/"]
    }
  ]
}
```

- **`default_browser`**: Browser for unmatched URLs (defaults to `Safari`). Accepts an app name (`"Google Chrome"`, `"Arc"`), full `.app` path (`"/Applications/Firefox.app"`), or bundle identifier (`"com.apple.Safari"`).
- **`rules`**: Evaluated in order; first match wins.
  - **`domains`**: Exact domain and subdomain match (`"claude.ai"` matches `claude.ai` and `platform.claude.ai`, not `notclaude.ai`).
  - **`url_prefixes`**: Prefix match against the full URL string.
- **`BROWSER_OPENING_ROUTER_CONFIG`**: Optional environment variable to override the config file path.

## Set as Default Browser

Launch **Browser Opening Router** from `/Applications` (or Spotlight) to open the built-in setup dialog:

- Click **Set as Default Browser** to trigger the macOS confirmation prompt.
- Click **Create & Open Config** / **Open Config** to edit `~/.config/browser-opening-router/config.json`.

You can also change it manually in **System Settings → Desktop & Dock → Default web browser**.

Test from Terminal:

```sh
open https://claude.com
open https://example.com
```

> Note: macOS routes links opened by *other* apps (Terminal, Slack, Mail, etc.). URLs typed directly into an already-open browser's address bar stay in that browser.

## Uninstall

Switch your default web browser back in System Settings, then run:

```sh
./scripts/uninstall.sh
```

## License

[MIT](LICENSE)
