# elevate-cli

A CLI for [Elevate24](https://www.jigsaw24.com/) — the macOS Privileged Access Management agent by Jigsaw24.

Elevate24 provides time-limited admin elevation via a menu bar app, but has no CLI, API, or AppleScript dictionary. This tool wraps macOS accessibility automation to give you full command-line control: request elevation, extend sessions, end sessions, and run commands with temporary admin privileges — all from your terminal.

## Quick Start

```bash
# Install
git clone https://github.com/chrisns/elevate-cli.git && cd elevate-cli
bash install.sh

# Check current status
elevate status

# Elevate and run a command
elevate start -- sudo softwareupdate -i -a

# Extend an active session
elevate extend

# End session early
elevate end
```

## Requirements

- macOS (tested on macOS 15 Sequoia)
- [Elevate24.app](https://www.jigsaw24.com/) installed and running in the menu bar
- Accessibility permission granted to your terminal app
- Touch ID — elevation requires physical biometric authentication and cannot be scripted

### Granting Accessibility Access

Your terminal app needs Accessibility permission to interact with Elevate24's UI:

**System Settings > Privacy & Security > Accessibility**

Add your terminal app (Terminal.app, iTerm2, Warp, Ghostty, etc.) to the list. You may need to restart your terminal after granting access.

## Commands

### `elevate status`

Shows whether you're currently elevated, session duration, and time remaining.

```
$ elevate status
ELEVATED
Session duration: 10 minutes
Menu bar: Elevate24 Unlocked
00:07:39
```

```
$ elevate status
NOT ELEVATED
Session duration: 10 minutes
Menu bar: Elevate24 Locked
```

### `elevate start [--reason "..."] [-- command ...]`

Opens the Elevate24 popover, selects a reason, clicks Start Session, and waits for Touch ID authentication.

```bash
# Default reason ("Run scripts")
elevate start

# Custom reason
elevate start --reason "System diagnostics"

# Run a command after elevation succeeds
elevate start -- sudo ls /var/root
elevate start -- sudo brew install ffmpeg
elevate start --reason "App install / update" -- sudo installer -pkg ./package.pkg -target /
```

When using `--`, the command after `--` runs immediately after elevation is confirmed. The exit code of the command is passed through.

**Touch ID is always required.** The user must physically authenticate — this is a security feature of Elevate24 and cannot be bypassed.

### `elevate extend`

Extends the current admin session by the configured duration (typically 10 minutes).

```
$ elevate extend
Extending admin session...
Session extended
```

### `elevate end`

Ends the current admin session and revokes privileges.

```
$ elevate end
Revoking admin privileges...
Admin privileges revoked
```

## Options

| Option | Description |
|--------|-------------|
| `--reason <text>` | Reason for elevation (`start` only). Default: "Run scripts" |
| `--quiet`, `-q` | Suppress informational output |
| `--no-color` | Disable colored output |
| `--timeout <sec>` | Max wait for UI operations. Default: 30 |
| `-- <command>` | Run command after elevation (`start` only) |
| `--help`, `-h` | Show help |
| `--version`, `-v` | Show version |

### Valid Reasons

Reasons are configured by your organisation via MDM. The defaults are:

- App install / update
- Software project debugging
- Development tooling configuration
- System diagnostics
- System configuration
- Responding to an incident
- Diagnosing issue with production systems
- Run scripts

## How It Works

Elevate24 is a SwiftUI menu bar app with no scripting interface. This CLI uses macOS Accessibility APIs (via `osascript` and System Events) to drive the UI programmatically:

1. **Status detection** uses `dseditgroup -o checkmember` to check admin group membership — this is ground truth, independent of the UI
2. **UI automation** clicks the menu bar item to open the popover, interacts with dropdown menus and buttons by their position in the accessibility hierarchy
3. **Authentication** cannot be automated — after clicking "Start Session", the CLI polls `dseditgroup` every 2 seconds waiting for the user to complete Touch ID
4. **Session management** uses the same positional button access for Extend (button 2) and End Session (button 1) in the active session view

### Why Positional Access?

Elevate24's SwiftUI buttons expose **no accessibility labels** — `name`, `title`, `help`, and `description` are all empty. The only reliable way to target them is by their position in the view hierarchy:

```
pop over 1 > group 1 > group 1
  button 1 = End Session
  button 2 = Extend
```

This has been verified by inspecting the live accessibility tree.

## Installation

```bash
bash install.sh
```

This creates a symlink from `/usr/local/bin/elevate` to the script. Requires `sudo` for the symlink.

To uninstall:

```bash
sudo rm /usr/local/bin/elevate
```

## Testing

```bash
bash test_elevate.sh
```

The test harness is self-contained with zero external dependencies. It sources the main script with `ELEVATE_TESTING=1` and overrides all external command wrappers (`osascript`, `dseditgroup`, `pgrep`, `defaults`) with mocks.

64 tests covering:
- Argument parsing and validation
- Status detection logic
- Preflight checks (app installed, running, accessibility)
- All command paths (status, start, extend, end, help)
- Output formatting and quiet mode
- Edge cases (stale menu bar state, blocked extension, credential parsing)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (preflight failure, UI automation error, timeout) |
| 2 | Usage error (bad arguments, unknown command) |

When using `-- <command>`, the exit code of the command is returned.

## Configuration

The CLI reads Elevate24's managed preferences at:

```
/Library/Managed Preferences/com.jigsaw24.Elevate24.plist
```

Key values used:
- `Sessiontime` — session duration in seconds (default: 600)
- `reasons` — list of valid elevation reasons
- `showAdminPasswordGrace` — how long credentials are visible (default: 30s)

These are configured by your organisation's MDM profile and cannot be changed locally.

## Compatibility

- **macOS**: Tested on macOS 15 (Sequoia), Apple Silicon
- **Bash**: Compatible with bash 3.2 (the macOS system default) — no brew/newer bash required
- **Elevate24**: Tested with v2.3.2
- **Shell**: Works from any terminal with Accessibility permission

## Project Structure

```
elevateautomate/
  elevate            # Main CLI script (bash, ~500 lines)
  test_elevate.sh    # Test harness (64 tests, zero dependencies)
  install.sh         # Symlinks to /usr/local/bin/elevate
  README.md
```

## Limitations

- **Touch ID cannot be automated.** This is by design — elevation requires physical presence.
- **Button discovery is positional.** If Jigsaw24 changes the Elevate24 UI layout, button positions may need updating.
- **One session at a time.** Elevate24 supports a single elevation session per user.
- **MDM-managed reasons.** The valid reason list comes from your organisation's MDM profile.

## License

MIT
