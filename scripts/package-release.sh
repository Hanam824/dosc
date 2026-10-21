#!/usr/bin/env bash
# Build the release files for one version into dist/:
#   dist/dosc-<version>-unsigned.ipa    Release build for devices, not code signed
#   dist/dosc-<version>-simulator.zip   Release build of Dosc.app for the iOS Simulator
#
#   ./scripts/package-release.sh v0.2.0
#   ./scripts/package-release.sh v0.2.1-nightly.20261021
#
# The marketing version is the version without `v` and any suffix (App Store rules: digits and dots);
# the build number is the commit count, so every build is higher than the last. Needs Xcode and
# XcodeGen. The last line printed is the IPA's path; the simulator zip is next to it.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:?usage: $0 <version, e.g. v0.2.0>}"
marketing="${version#v}"
marketing="${marketing%%-*}"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
derived=".build/release-derived"
out="dist"
ipa="$out/dosc-$version-unsigned.ipa"
sim_zip="$out/dosc-$version-simulator.zip"

xcodegen generate --quiet
rm -rf "$derived" "$out/Payload"
mkdir -p "$out"

common=(
    -project Dosc.xcodeproj -scheme Dosc -configuration Release -derivedDataPath "$derived"
    MARKETING_VERSION="$marketing" CURRENT_PROJECT_VERSION="$build_number"
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
)

echo "Building $version ($marketing, build $build_number) for devices..." >&2
xcodebuild build "${common[@]}" -destination 'generic/platform=iOS' -quiet >&2
mkdir -p "$out/Payload"
cp -R "$derived/Build/Products/Release-iphoneos/Dosc.app" "$out/Payload/"
rm -f "$ipa"
(cd "$out" && zip -qr "$(basename "$ipa")" Payload)
rm -rf "$out/Payload"

echo "Building $version for the iOS Simulator..." >&2
xcodebuild build "${common[@]}" -destination 'generic/platform=iOS Simulator' -quiet >&2
rm -f "$sim_zip"
(cd "$derived/Build/Products/Release-iphonesimulator" && zip -qry "$OLDPWD/$sim_zip" Dosc.app)

echo "$sim_zip"
echo "$ipa"
