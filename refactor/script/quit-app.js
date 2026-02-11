#!/usr/bin/osascript -l JavaScript
'use strict';

ObjC.import('stdlib');

function run(argv) {
  var bundleId = argv[0];
  var app;

  try {
    app = Application(bundleId);
    if (app.running()) {
      try {
        app.quit();
      } catch (err) {
        // Ignore harmless -128 "User canceled"
        if (app.running()) {
          $.exit(1);
        }
      }
    }
    $.exit(0);
  } catch (err) {
    // Couldn't resolve bundle ID
    $.exit(1);
  }
}
