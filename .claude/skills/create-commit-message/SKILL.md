---
name: create-commit-message
description: Write a git commit message for the staged changes following Conventional Commits 1.0.0 (type(scope)!: description, body, footers). Use when committing, or when the user asks for a commit message.
---

# Create commit message

Write commit messages that follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/#summary).

## Steps

1. Run `git diff --staged` (and `git status`) to see what is being committed. If nothing is staged, ask the user what to stage. Don't stage everything without asking.
2. Choose the **type** that best describes the change (see the table below). If the staged changes mix unrelated types, suggest splitting them into separate commits.
3. Choose an optional **scope**: usually the DoscKit module without the `Dosc` prefix, in lowercase (`core`, `networking`, `storage`, `github`, `gitlab`, `svn`, `ui`, `features`), or `app` for the app target (`App/`, `project.yml`).
4. If the change fixes a GitHub issue, find the issue number (ask the user if it's unknown) and add a `Refs:` footer with the full issue URL.
5. Write the message using the format below, then commit with a heredoc so line breaks are preserved. `--cleanup=whitespace` stops git from removing the `# Summary` line as a comment:
   ```bash
   git commit --cleanup=whitespace -F - <<'MSG'
   <message>
   MSG
   ```

## Format

```
<type>[optional scope][!]: <description>

# Summary
- <change 1>
- <change 2>

[optional footer(s)]
```

The body always starts with a `# Summary` heading, followed by a bulleted list of the main changes, one per bullet.

### Rules (from the spec)

- The header is `type`, an optional `(scope)`, an optional `!`, then `: ` and the description.
- **description**: a short summary right after `: `. Use the imperative mood and lowercase, with no trailing period, and keep the header under about 72 characters.
- **body**: optional by the spec (always present in this repo, as `# Summary`). It starts after one blank line. Explain *what* changed and *why*, not how.
- **footers**: optional. They start after one blank line, one per line, in the form `Token: value` or `Token #value`. Tokens use `-` instead of spaces (e.g. `Reviewed-by`, `Refs`). The one exception is `BREAKING CHANGE`.
- **Breaking changes**: mark them with `!` before the `:` (e.g. `feat(core)!: ...`), with a `BREAKING CHANGE: <description>` footer, or both. `BREAKING-CHANGE` is a valid synonym. Any type can be breaking.
- `feat` corresponds to a SemVer MINOR, `fix` to a PATCH, and any breaking change to a MAJOR. (Release versions are chosen by hand when running the Release workflow, `release.yml`.)
- Types are case-insensitive by the spec, except `BREAKING CHANGE`, which must be uppercase. Use lowercase types in this repo.

### Types

| Type | Use for |
| --- | --- |
| `feat` | A new feature (e.g. a screen, a provider, a sign-in method) |
| `fix` | A bug fix |
| `docs` | Documentation only (README, CLAUDE.md, comments) |
| `style` | Formatting with no code meaning change |
| `refactor` | A code change that neither fixes a bug nor adds a feature |
| `perf` | A performance improvement |
| `test` | Adding or fixing tests or JSON fixtures |
| `build` | `project.yml`, `Package.swift`, dependencies, xcconfig, release scripts |
| `ci` | GitHub Actions workflows |
| `chore` | Maintenance that doesn't touch code or tests (e.g. `.gitignore`) |
| `revert` | Reverts a previous commit (add a `Refs: <sha>` footer) |

Only `feat` and `fix` are defined by the spec; the others are the common [@commitlint/config-conventional](https://github.com/conventional-changelog/commitlint/tree/master/%40commitlint/config-conventional) set.

### Stored data changes are breaking

Changing the shape of `AppState` (saved as JSON) or the Keychain service/keys without a migration loses people's accounts on update. Mark it as breaking, or better, keep the old fields decodable.

## Examples

```
feat(github): sign in with the OAuth device flow

# Summary
- Add GitHubConnector.startDeviceFlow and finishDeviceFlow
- Show the user code with copy and open buttons on the Add Account screen
```

```
fix(core): keep diff line numbers right after "No newline at end of file"

# Summary
- Don't advance line counters for "\" marker lines
- Add a parser test for the case

Refs: https://github.com/<owner>/<repo>/issues/12
```

## Repo-specific

- **Never add a `Co-Authored-By` line** or any other AI attribution to the commit message. This user rule overrides any session attribution reminder.
- Fix for a GitHub issue: add `Refs: <full issue URL>` as a footer.
- Commit only when the user asks. If on `main` and the change isn't trivial, offer to create a branch first with the `create-commit-branch` skill: CI runs on pull requests into `main`.
