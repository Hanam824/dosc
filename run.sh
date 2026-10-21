#!/usr/bin/env bash
# Build dosc and run it on the iOS Simulator or on a connected iPhone/iPad.
#
#   ./run.sh                         # Simulator, default device (iPhone 17, or $SIM)
#   ./run.sh sim "iPhone 17 Pro"     # Simulator, a given device name or UDID
#   ./run.sh device                  # the first connected device (needs TEAM_ID, see below)
#   ./run.sh device <udid>           # a given connected device
#   ./run.sh list                    # list simulators and connected devices
#
# Options (environment variables):
#   CONFIG=Release        build configuration (default Debug)
#   TEAM_ID=XXXXXXXXXX    Apple team for device builds. With a free Apple ID, add it in Xcode →
#                         Settings → Accounts once; the team ID is shown there (Personal Team) or in
#                         an Apple Development certificate's "OU". Apps signed this way run 7 days.
#
# Simulator builds are unsigned. Device builds let Xcode create the provisioning profile
# (-allowProvisioningUpdates), so the Apple ID must be signed in to Xcode.
set -euo pipefail

cd "$(dirname "$0")"

# xcodebuild/simctl need Xcode, not just the Command Line Tools.
if ! xcode-select -p 2>/dev/null | grep -q '\.app/'; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

bundle_id="app.dosc.ios"
config="${CONFIG:-Debug}"
derived=".build/run-derived"
mode="${1:-sim}"

die() { echo "error: $*" >&2; exit 1; }

command -v xcodegen > /dev/null || die "XcodeGen is missing: brew install xcodegen"

generate() {
    xcodegen generate --quiet
}

build() { # <destination> [extra settings...]
    local destination="$1"
    shift
    echo "Building $config for $destination..." >&2
    xcodebuild build -project Dosc.xcodeproj -scheme Dosc -configuration "$config" \
        -destination "$destination" -derivedDataPath "$derived" -quiet "$@" >&2
}

run_simulator() {
    local name="${1:-${SIM:-iPhone 17}}"
    # Accept a UDID or a name; take the first available device with that name.
    local udid
    udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds]
match = next((d for d in devices if d["udid"] == want or d["name"] == want), None)
print(match["udid"] if match else "")
' "$name")"
    [ -n "$udid" ] || die "no available simulator named '$name' (see ./run.sh list)"

    generate
    build "id=$udid" CODE_SIGNING_ALLOWED=NO
    local app="$derived/Build/Products/$config-iphonesimulator/Dosc.app"

    echo "Booting $name..." >&2
    xcrun simctl boot "$udid" 2> /dev/null || true # already booted is fine
    open "${DEVELOPER_DIR:-$(xcode-select -p)}/Applications/Simulator.app" --args -CurrentDeviceUDID "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null

    echo "Installing and launching..." >&2
    xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
    xcrun simctl install "$udid" "$app"
    xcrun simctl launch "$udid" "$bundle_id" > /dev/null
    echo "dosc is running on $name ($udid)."
}

run_device() {
    local udid="${1:-}"
    [ -n "${TEAM_ID:-}" ] || die "set TEAM_ID to your Apple team ID, e.g. TEAM_ID=ABCDE12345 ./run.sh device"

    if [ -z "$udid" ]; then
        local json
        json="$(mktemp)"
        xcrun devicectl list devices --json-output "$json" > /dev/null
        udid="$(python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
ready = [d for d in devices if d.get("hardwareProperties", {}).get("platform") == "iOS"
         and d.get("connectionProperties", {}).get("tunnelState") != "unavailable"]
print(ready[0]["hardwareProperties"]["udid"] if ready else "")
' "$json")"
        rm -f "$json"
        [ -n "$udid" ] || die "no connected iPhone or iPad found (connect it, unlock it and trust this Mac)"
    fi

    generate
    build "id=$udid" DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
    local app="$derived/Build/Products/$config-iphoneos/Dosc.app"

    echo "Installing on $udid..." >&2
    xcrun devicectl device install app --device "$udid" "$app" > /dev/null
    echo "Launching..." >&2
    if ! xcrun devicectl device process launch --device "$udid" --terminate-existing "$bundle_id" > /dev/null; then
        echo "Installed, but iOS refused to launch it. On the device, trust the developer in" >&2
        echo "Settings → General → VPN & Device Management, then open dosc." >&2
        exit 1
    fi
    echo "dosc is running on device $udid."
}

case "$mode" in
    sim | simulator) run_simulator "${2:-}" ;;
    device) run_device "${2:-}" ;;
    list)
        echo "Simulators:"
        xcrun simctl list devices available | grep -E '^\s+iP(hone|ad)' || true
        echo
        echo "Devices:"
        xcrun devicectl list devices 2> /dev/null || true
        ;;
    -h | --help | help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown mode '$mode' (use sim, device, list or help)" ;;
esac
