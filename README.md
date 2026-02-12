![bbl](assets/refresh-dot-light.svg#gh-dark-mode-only)![bbl](assets/refresh-dot-dark.svg#gh-light-mode-only)

# Babble

An automated upgrade routine for Homebrew (formulae + casks), Mac App Store apps, and macOS system updates, written as a modular Ruby application.

## Features

- **Homebrew upgrades**: Automatically upgrades outdated formulae and casks
- **Mac App Store upgrades**: Integrates with `mas` CLI to upgrade Mac App Store apps
- **macOS system updates**: Runs `softwareupdate` for system updates
- **Smart app lifecycle management**:
  - Detects running apps that need to be quit for upgrade
  - Shows native macOS alerts for critical apps (configurable via `unsafe_to_quit`)
  - Automatically reopens apps after upgrade completes
- **Gatekeeper quarantine removal**: Removes quarantine attributes from cask app bundles
- **Interactive workflow**: Space-bar-to-continue prompts between stages

## Architecture

Babble uses a clean, modular architecture with clear separation of concerns:

- **Bash wrapper** (`bin/babble`): Loads Homebrew environment and executes Ruby orchestrator
- **Ruby orchestrator** (`lib/babble/`): Modular library handling upgrade logic
- **Swift GUI** (`swift/src/quit_alert.swift`): Native macOS alerts (auto-compiled on first use)
- **Unified config** (`config/apps.yml`): YAML configuration for app management

## Example session

![Example](assets/demo-241211-2018-x2.svg)

## Install

```shell
# Clone the repository
git clone https://github.com/toobuntu/babble.git
cd babble

# Run directly
bin/babble

# Or symlink to your PATH
ln -s "$(pwd)/bin/babble" "$HOME/bin/babble"
babble
```

## Configuration

Edit `config/apps.yml` to customize which apps should be quit/reopened during upgrades:

```yaml
apps:
  homebrew:
    - token: iterm2
      bundle_ids:
        - com.googlecode.iterm2
      unsafe_to_quit: true  # Show confirmation dialog before quitting
    - token: google-chrome
      bundle_ids:
        - com.google.Chrome
      unsafe_to_quit: true
  mas:
    - app_id: 1595464182
      name: MonitorControlLite
      bundle_ids:
        - app.monitorcontrol.MonitorControlLite
      unsafe_to_quit: true
```

## Requirements

- macOS 13+ (Ventura or later)
- Homebrew installed
- Ruby (provided by Homebrew)
- Optional: `mas` CLI for Mac App Store upgrades (`brew install mas`)
- Optional: `yq` for config file reorganization (`brew install yq`)

## Usage

```sh
babble
```

The tool will:
1. Check for outdated Homebrew packages
2. Quit configured apps that are running
3. Upgrade all outdated packages
4. Reopen apps that were quit
5. Proceed to Mac App Store upgrades
6. Proceed to macOS system updates

## Module Structure

| Module | Responsibility |
|--------|---------------|
| `ConfigManager` | Load, validate, and merge YAML config (shared by brew and MAS) |
| `BrewUpgrade` | Detect outdated packages, quit apps, upgrade, reopen apps |
| `MasUpgrade` | Same workflow for Mac App Store apps |
| `MacOSUpdate` | `softwareupdate` wrapper |
| `AppManager` | Detect running apps, quit, invoke Swift GUI, reopen |
| `BundleLauncher` | Multi-tier app reopen logic with fallbacks |
| `QuarantinePurger` | Remove Gatekeeper quarantine xattrs |
| `Waiter` | Interactive terminal prompts |
| `Orchestrator` | Top-level flow coordination |

---

#### Babble uses the following open source icons:

  - [Tabler Icons](https://github.com/tabler/tabler-icons) ([MIT License](https://en.wikipedia.org/wiki/MIT_License).
The full license text is available in [LICENSE](https://github.com/tabler/tabler-icons/blob/master/LICENSE).)

### License

Babble is licensed under the [GPLv3 License](https://en.wikipedia.org/wiki/GNU_General_Public_License).
The full license text is available in [LICENSE](https://github.com/toobuntu/babble/blob/master/LICENSE).
