<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

![bbl](assets/refresh-dot-light.svg#gh-dark-mode-only)![bbl](assets/refresh-dot-dark.svg#gh-light-mode-only)

<!--
![bbl](assets/refresh-dot-grey.svg)
-->

# Babble

An interactive upgrade routine for Homebrew (formulae and casks), Mac
App Store apps via `mas`, and macOS system updates via
`softwareupdate`.

> **Migration in progress.** Babble is being rewritten as a Homebrew
> external command (`brew babble`) in this repository — the
> `toobuntu/babble` tap (repo renamed `homebrew-babble` 2026-07-06).
> The released, working version remains the ksh script `bbl` —
> use [v0.5.2](https://github.com/toobuntu/homebrew-babble/releases/tag/v0.5.2).
> Plan and status: [docs/handoff.md](docs/handoff.md) and
> [docs/technical-debt.md](docs/technical-debt.md); design:
> [docs/architecture.md](docs/architecture.md) and
> [docs/decisions/](docs/decisions/).

## Example session

![Example](assets/demo-241211-2018-x2.svg)

## Install

### Released ksh version (v0.5.2 — current)

```shell
# Download the script
curl --silent --show-error --fail "https://raw.githubusercontent.com/toobuntu/homebrew-babble/v0.5.2/bbl" --output "<path>/bbl" && chmod +x "<path>/bbl"
# Run it
"<path>/bbl"
```

Change `<path>` to the path of your choice. `"$HOME/Downloads"`,
`"$HOME/bin"` and `"$HOME/devel"` are all common possibilities.

### Homebrew external command (functional at v0.6.0)

```shell
brew tap toobuntu/babble
brew babble
```

Not yet functional — `brew babble` currently prints a stub banner
while the upgrade phases are ported (see
[docs/handoff.md](docs/handoff.md) § Block C).

## Usage

```sh
bbl
```

---

#### Babble uses the following open source icons:

  - [Tabler Icons](https://github.com/tabler/tabler-icons) ([MIT License](https://en.wikipedia.org/wiki/MIT_License).
The full license text is available in [LICENSE](https://github.com/tabler/tabler-icons/blob/master/LICENSE).)

### License

Babble is licensed under the [GPLv3 License](https://en.wikipedia.org/wiki/GNU_General_Public_License).
The full license text is available in [LICENSE](https://github.com/toobuntu/homebrew-babble/blob/master/LICENSE).
