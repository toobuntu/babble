<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Implementation Summary

## Overview

This PR successfully rewrites babble from the existing ksh implementation to a clean, modular Ruby application that orchestrates upgrades for Homebrew (formulae + casks), Mac App Store apps, and macOS system updates.

## Key Deliverables

### 1. Directory Structure
```
babble/
├── bin/babble                 # Bash wrapper entry point
├── config/apps.yml           # Unified YAML configuration
├── lib/babble/               # Ruby modules
│   ├── cli.rb               # CLI entry point
│   ├── orchestrator.rb      # Top-level flow coordination
│   ├── brew_upgrade.rb      # Homebrew upgrade logic
│   ├── mas_upgrade.rb       # Mac App Store upgrade logic
│   ├── macos_update.rb      # macOS system updates
│   ├── app_manager.rb       # App lifecycle management
│   ├── bundle_launcher.rb   # Multi-tier app reopen
│   ├── config_manager.rb    # Config validation (shared)
│   ├── quarantine_purger.rb # Gatekeeper xattr removal
│   ├── waiter.rb           # Interactive prompts
│   └── constants.rb         # Shared constants
└── swift/src/quit_alert.swift # Native macOS alert GUI
```

### 2. Architecture Highlights

**Bash Entry Point (`bin/babble`)**
- Loads brew.env files in correct order
- Sources Homebrew's utils/ruby.sh to find HOMEBREW_RUBY_PATH
- Execs Ruby orchestrator with full environment

**Ruby Orchestrator**
- Modular design with clear separation of concerns
- ConfigManager eliminates duplication (shared by brew and MAS)
- Sequential flow: brew_upgrade → mas_upgrade → macos_update

**Swift GUI**
- Auto-compiled on first use via `xcrun swiftc`
- Cached to `~/.cache/babble/quit_alert`
- Dark/light mode support with embedded SVG icons
- Exit codes: 0=Continue, 1=Cancel, 2=icon error, 3=usage error

### 3. Bug Fixes from Prototype

1. **quit_message validation bug**: Fixed variable scoping issue where `existing_value` and `new_value` referenced variables from wrong scope
2. **Config duplication**: Extracted validation logic to shared ConfigManager
3. **Commented-out code**: Zero commented-out code in final implementation
4. **Message flow**: Fixed duplicate/misleading messages with custom continuation parameter

### 4. Security

- Fixed ReDoS vulnerability in bundle ID validation regex
- Changed from `/\A[a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+\z/i` (nested quantifiers)
- To `/\A[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?(?:\.[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?)+\z/i`
- CodeQL security scan: 0 alerts

### 5. Code Quality

- All Ruby files use `typed: strict` and `frozen_string_literal: true`
- Minimal comments; self-documenting code
- Follows DRY and YAGNI principles
- No trailing whitespace
- Shared constants extracted (CACHE_DIR)

### 6. Testing

- Updated `script/syntax` to check Ruby files
- Updated `script/style` to check bash wrapper
- All syntax checks pass
- Code review completed with all issues addressed

## What's NOT Included (Per Scope Exclusions)

- No Homebrew external command (brew cupr) - will be separate tap
- No running formulae detection - only GUI apps via lsappinfo
- No pre-built Swift binaries - auto-compile only
- No full Sorbet sig type signatures (typed: strict is sufficient)

## Configuration Example

```yaml
apps:
  homebrew:
    - token: iterm2
      bundle_ids:
        - com.googlecode.iterm2
      unsafe_to_quit: true
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
- Optional: `mas` for Mac App Store upgrades
- Optional: `yq` for config reorganization

## Usage

```bash
bin/babble
```

The tool will:
1. Check for outdated Homebrew packages
2. Quit configured apps that are running
3. Upgrade all outdated packages
4. Reopen apps that were quit
5. Proceed to Mac App Store upgrades
6. Proceed to macOS system updates

## Commits

1. Initial plan
2. Implement core Ruby modules and infrastructure
3. Add .gitignore and update test scripts for Ruby
4. Update README for new Ruby implementation
5. Fix code review issues: trailing whitespace and shared constants
6. Fix ReDoS vulnerability in bundle ID validation regex

## Review Status

- ✅ Code review completed
- ✅ Security scan completed (0 alerts)
- ✅ All issues addressed
- ✅ Ready for merge
