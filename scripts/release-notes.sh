#!/usr/bin/env bash
# Print the part of a GitHub release's notes that says which file to download and how to install it.
#
#   ./scripts/release-notes.sh v0.2.0
#
# Used by release.yml and nightly-release.yml; the file names match package-release.sh.
set -euo pipefail

version="${1:?usage: $0 <version, e.g. v0.2.0>}"

cat <<NOTES
Files:
- \`dosc-$version-unsigned.ipa\`: the iPhone/iPad app, **not signed**.
- \`dosc-$version-simulator.zip\`: \`Dosc.app\` for the iOS Simulator (unzip, then drag it onto a running simulator or run \`xcrun simctl install booted Dosc.app\`).

dosc has no App Store or TestFlight build yet, so the IPA must be signed with your own Apple ID to install it on a device: use [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) with a free Apple ID (the app then runs for 7 days before it must be refreshed), or build it from source in Xcode with your Personal Team.
NOTES
