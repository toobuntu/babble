# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Invisible-Unicode / Trojan Source (CVE-2021-42574) scanner: the python3
# detector for scripts/lint-unicode.sh (which passes the newline-delimited
# file list as argv[1]). Lives in its own file rather than a shell heredoc:
# Homebrew's shfmt wrapper (brew style --fix) applies line-based alignment
# transforms that are not heredoc-aware and corrupt embedded Python — that
# is how repo-foundation's canonical copy got mangled. Upstream this split
# to repo-foundation.
#
# Mirrors Red Hat's RHSB-2021-007 approach: flag every character in Unicode
# category Cf (Format), extended to Cc (Control) minus a TAB/LF/CR allowlist.
# Future-proof: invisible characters added to Cf/Cc in later Unicode
# revisions are caught when the runner's python3 updates. Per-file opt-out
# via a `bidi-allow: U+XXXX,U+YYYY` annotation anywhere in the file.

import pathlib
import re
import sys
import unicodedata

ALLOWED = {0x09, 0x0A, 0x0D}  # TAB, LF, CR
ALLOW_RE = re.compile(r'bidi-allow:\s*([U+0-9A-Fa-f,]+)')


def parse_allow(text):
    m = ALLOW_RE.search(text)
    if not m:
        return frozenset()
    cps = set()
    for token in m.group(1).split(','):
        token = token.strip()
        if token.startswith('U+'):
            try:
                cps.add(int(token[2:], 16))
            except ValueError:
                pass
    return frozenset(cps)


def is_suspicious(ch, allow):
    cp = ord(ch)
    if cp in ALLOWED or cp in allow:
        return False
    return unicodedata.category(ch) in ('Cf', 'Cc')


def main():
    with open(sys.argv[1]) as fh:
        paths = [line.rstrip('\n') for line in fh if line.strip()]

    bidi_failures = []
    utf8_failures = []
    for p in paths:
        path = pathlib.Path(p)
        if not path.is_file():
            continue
        try:
            with path.open('rb') as fh:
                head = fh.read(4096)
                if b'\x00' in head:
                    # A NUL alone does not prove "binary": UTF-16/UTF-32
                    # text contains NULs but is still text we reject under
                    # the UTF-8 policy.
                    for enc in ('utf-16', 'utf-32'):
                        try:
                            head.decode(enc)
                        except UnicodeDecodeError:
                            continue
                        utf8_failures.append(
                            f'{path} (looks like {enc}; project requires UTF-8)')
                        break
                    # NUL but not decodable as UTF-16/32: treat as binary
                    # and skip, mirroring RHSB-2021-007's text/* MIME gate.
                    # Falling through to the UTF-8 check would mis-flag
                    # tracked binaries as violations.
                    continue
                raw = head + fh.read()
        except OSError:
            continue
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            utf8_failures.append(str(path))
            continue
        allow = parse_allow(text)
        if any(is_suspicious(c, allow) for c in text):
            bidi_failures.append(str(path))

    ok = True
    if utf8_failures:
        print('Files violating UTF-8-without-BOM policy:', file=sys.stderr)
        for f in utf8_failures:
            print(f'  {f}', file=sys.stderr)
        ok = False
    if bidi_failures:
        print('Invisible Unicode characters found (CVE-2021-42574):',
              file=sys.stderr)
        for f in bidi_failures:
            print(f'  {f}', file=sys.stderr)
        print('', file=sys.stderr)
        print('A file may opt out of specific codepoints with an in-file',
              file=sys.stderr)
        print('annotation, e.g.:  // bidi-allow: U+200E,U+200F',
              file=sys.stderr)
        ok = False
    if not ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
