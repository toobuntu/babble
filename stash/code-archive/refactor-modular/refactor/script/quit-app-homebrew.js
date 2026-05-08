#!/usr/bin/osascript -l JavaScript

// SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
//
// SPDX-License-Identifier: GPL-3.0-or-later

'use strict';

ObjC.import('stdlib')

function run(argv) {
  var app = Application(argv[0])

  try {
    app.quit()
  } catch (err) {
    // If it's just the "User canceled"/no reply case, ignore
    if (err.number !== -128) {
    } else if (app.running()) {
      $.exit(1)
    }
  }

  $.exit(0)
}
