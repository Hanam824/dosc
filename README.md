# dosc

A native iOS app for viewing all your source-control accounts in one place, read-only. It is designed after the GitHub iOS app.

- **Phase 1 (now):** GitHub and GitHub Enterprise Server: repositories, code browser with syntax highlighting, README, commit history and diffs, issues and pull requests (conversation, files, commits), notifications and the activity feed. You can view several accounts at once or switch between them.
- **Next:** GitLab, then Subversion.

dosc never creates, edits or deletes anything on your servers. Tokens are stored in the iOS Keychain.

## Build

Requirements: Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Dosc.xcodeproj
```

Or from the terminal:

```sh
./run.sh                          # build and launch on the iOS Simulator (iPhone 17; ./run.sh sim "<name>" for another)
TEAM_ID=<your team ID> ./run.sh device   # build, install and launch on a connected iPhone
./run.sh list                     # available simulators and devices
```

To run on your iPhone without a paid developer account, pick your Apple ID's free **Personal Team** under Signing & Capabilities. The app runs for 7 days before you reinstall it.

### Sign in

- **Token:** create a [fine-grained token](https://github.com/settings/personal-access-tokens/new) with read-only access to Contents, Issues, Pull requests and Metadata (or a classic token with `repo`, `read:org`, `notifications`).
- **Sign in with GitHub (device flow):** register an OAuth App with Device Flow enabled, then put its client ID in `Config/Secrets.xcconfig` (see `Config/Secrets.example.xcconfig`).

## Releases

Unsigned builds are attached to GitHub releases: `dosc-<version>-unsigned.ipa`, to sideload with AltStore or Sideloadly, and a simulator build. See [CLAUDE.md](CLAUDE.md) for the architecture, CI and release process.
