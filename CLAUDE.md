# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**dosc** is a native iOS app (SwiftUI, iOS 17+) for viewing many source-control accounts in one place. Its design follows the GitHub iOS app. It is **read-only**: it browses code, history, diffs, issues, pull requests, notifications and activity, and never changes anything on a server.

- Phase 1 (now): GitHub and GitHub Enterprise Server. Sign-in is by personal access token, or by OAuth device flow when `GITHUB_CLIENT_ID` is set.
- Phase 2: GitLab (`DoscGitLab`, REST v4: merge requests map to change requests).
- Phase 3: Subversion (`DoscSVN`, WebDAV `PROPFIND`/`REPORT` over HTTPS: no issues or change requests, so its capabilities leave them out and the screens hide them).

## Commands

```sh
swift test --package-path Packages/DoscKit                    # package tests on macOS (fast)
swift test --package-path Packages/DoscKit --filter GitHub    # some tests
xcodegen generate                                             # Dosc.xcodeproj from project.yml (git-ignored)
xcodebuild test -project Dosc.xcodeproj -scheme Dosc \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO   # app + package tests on iOS
swift format format -i --recursive App AppTests Packages/DoscKit/Sources Packages/DoscKit/Tests Packages/DoscKit/Package.swift
swift format lint --strict --recursive App AppTests Packages/DoscKit/Sources Packages/DoscKit/Tests Packages/DoscKit/Package.swift
./scripts/package-release.sh v0.0.0-local                     # unsigned IPA + simulator zip in dist/
./run.sh                                                      # build, install and launch on the Simulator
TEAM_ID=<team> ./run.sh device                                # same on a connected iPhone (free Personal Team works)
```

If `xcodebuild` says it needs Xcode, not the Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Install XcodeGen with `brew install xcodegen`.

There is no paid Apple Developer account, so every build is unsigned (`CODE_SIGNING_ALLOWED=NO`). To run on a device, open the project in Xcode and pick a free Personal Team (the app expires after 7 days), or sideload a release IPA with AltStore or Sideloadly.

For "Sign in with GitHub", copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (git-ignored) and set the client ID of an OAuth App that has Device Flow enabled. Release builds read it from the repository variable `GITHUB_CLIENT_ID`.

## Git workflow and CI

- Branch names and commit messages follow Conventional Commits. Use the `create-commit-branch` and `create-commit-message` skills in `.claude/skills/`. **Never add `Co-Authored-By` or other AI attribution to commits** (a user rule that overrides any session attribution reminder). Commit only when asked.
- Work goes through pull requests into `main`. `ci.yml` runs only on pull requests (and manually), on macOS: `swift format lint --strict`, `swift test` for the package, and `xcodebuild test` on an iPhone simulator. Doc-only changes skip the build (`scripts/code-changes.sh` defines what counts as docs). Make **`CI result`** the required status check on `main`.
- Releases are made by hand: `release.yml` (Actions → Release → Run workflow) takes a version like `v0.2.0`, builds `main`, creates that tag and publishes a GitHub release marked latest. The release and the nightly build both use `build-release.yml`, which tests the commit and runs `scripts/package-release.sh <version>` to produce `dosc-<version>-unsigned.ipa` and `dosc-<version>-simulator.zip`.
- `nightly-release.yml` runs at 17:00 UTC (00:00 in Vietnam). When `main` has non-doc commits since the last nightly build or release, it builds them as `v<next patch>-nightly.<date>` (`scripts/nightly-version.sh`) and replaces the `nightly` pre-release. It never creates version tags.

## Architecture

`project.yml` describes the thin app target (`App/`: `DoscApp.swift` wires up connectors, storage and `RootView`) and its tests (`AppTests/`). All logic lives in the local package `Packages/DoscKit`.

Dependency direction (lower layers never depend on higher ones):

```
DoscCore            models, SourceControlProvider / ProviderConnector protocols, UnifiedDiffParser
DoscNetworking      HTTPClient (read-only), FormPoster (OAuth sign-in only), LinkHeader, ETag cache
DoscCore → DoscStorage                 KeychainTokenStore, AppStateStore (accounts, recents; JSON)
DoscCore + DoscNetworking → DoscGitHub GitHubProvider, GitHubConnector, DTOs → GitHubMapper
DoscCore → DoscUI                      Palette (Primer colors), components, DiffView, CodeView, MarkdownText
DoscCore + DoscStorage + DoscUI → DoscFeatures   AppModel, PagedList, screens, Route navigation
App → DoscFeatures + DoscGitHub (+ Networking, Storage)
```

- **Providers**: one `SourceControlProvider` per account. `capabilities` lists what it supports, and the default protocol implementations throw `ProviderError.unsupported`. Repositories are identified by `RepoRef(path:)`, which works for `owner/name`, GitLab group paths and SVN roots. Pages use an opaque `PageCursor`; GitHub stores the `Link: rel="next"` URL in it. Providers map server errors to `ProviderError` so every screen shows the same messages.
- **Connectors**: `ProviderConnector` signs in (token or device flow) and builds providers. `AppModel` gets one connector per `ProviderKind` from the app, so `DoscFeatures` never imports a concrete provider. Adding GitLab or SVN means writing a new module and adding its connector in `DoscApp.swift`. The screens don't change.
- **Multiple accounts**: `AppModel.selection` is `.all` or one account. List screens build `PagedList` sources from `activeAccounts` (`sources(app, needs:)` in `HomeView.swift`), fetch them in parallel, keep a cursor per account, and merge the results by date. When more than one account is shown, rows show an `AccountBadge`.
- **Navigation**: every push is a `Route` value. `RouteView` resolves the account's provider and builds the screen; register it with `.routeDestinations()` on each tab's `NavigationStack`.
- **GitHub**: REST v3 only (no GraphQL, which would need `POST`). The API base is `api.github.com` for github.com and `<host>/api/v3` for Enterprise. File contents and READMEs are fetched with `Accept: application/vnd.github.raw`. "Involving me" issue and PR lists use `search/issues` with `involves:<login>`. The repository issues endpoint also returns PRs, which get filtered out.

## Conventions

- Swift 6 language mode with strict concurrency. Models are `Sendable` value types, view state is `@MainActor @Observable`, and providers are `Sendable` structs.
- `swift format` with `.swift-format` (120 columns). CI fails on lint warnings.
- Tests use Swift Testing (`import Testing`). Network tests go through `StubProtocol` (one per test target), which gives each session its own handler, so suites can run in parallel. GitHub responses are recorded as JSON fixtures in `Tests/DoscGitHubTests/Fixtures`.
- `DoscKit` also builds for macOS 14 so `swift test` runs without a simulator. Guard UIKit-only APIs with `#if canImport(UIKit)` / `#if os(iOS)`.
- Document public types and anything non-obvious with `///`: start with one sentence saying what it is or does.
- Work that isn't done goes in the phase list above, not into the code as stubs.

## Invariants

- **Read-only.** `HTTPClient` can only send `ReadOnlyMethod` (GET, HEAD, PROPFIND, REPORT), and a test pins that set. The only `POST`s are `FormPoster` calls to OAuth sign-in endpoints. Never add a writing endpoint or a UI action that changes server state. Removing an account only removes it from dosc.
- **Secrets stay in the Keychain.** Tokens live only in `KeychainTokenStore` (`AfterFirstUnlockThisDeviceOnly`), keyed by `Account.id`. `AppState` (on disk) and logs never contain them. Cache keys include the request headers, so accounts never share cached responses.
- Screens talk to `SourceControlProvider` and `ProviderConnector` only. Nothing in `DoscFeatures` or `DoscUI` depends on a specific server.
