#! /bin/ksh

/bin/rm -rf ./refactor/swift/build/dist
/bin/mkdir -p ./refactor/swift/build/dist

for arch in x86_64 arm64; do
  xcrun --sdk macosx swiftc \
    -O -whole-module-optimization \
    -Xfrontend -enable-ossa-modules \
    -Xlinker -dead_strip \
    -warn-concurrency -strict-concurrency=complete \
    -target "${arch}-apple-macos13" \
    -o "./refactor/swift/build/dist/quit_alert_${arch}" \
    ./refactor/swift/src/quit_alert.swift
  xcrun strip -Sx "./refactor/swift/build/dist/quit_alert_${arch}"
done
