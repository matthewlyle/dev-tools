---
name: change-workflow
description: The workflow for every change to the dev-tools app (a fix, a feature, a refactor, a doc edit) from branch to merged pull request. Use for any task that edits the repo; ends with a pre-merge checklist distilled from AGENTS.md. Not for releases (release-workflow).
---

# Making a change

Branch, do the work, verify, check, commit, open a pull request, review, merge on approval. `AGENTS.md` holds the rules; this is the order they're applied in and the checks that catch what slips on every merge.

## 1. Start

- `git fetch -q origin && git switch -c <short-kebab-name> origin/main`. An agent started by `work-issue` is already in its own worktree; its branch is the one to use. Never commit on `main` or on a branch you didn't create.
- Building on an unmerged branch of yours? Branch from it instead (stacked), open its pull request against that branch, and say so; merge from the bottom of the stack up.

## 2. Work

Read the `AGENTS.md` sections the change touches before editing. Reuse the existing pattern; a second convention beside it is a bug. Unmerged commits on your own branch can be amended; merged ones never.

## 3. Verify

Both must print SUCCEEDED before a commit. Gate the commit on them (`&&` or an explicit check) — a `;` chain commits over a failed test. `CODE_SIGNING_ALLOWED=NO` lets them run on a Mac with no signing account (mini, CI); no test touches the Keychain.

```sh
xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/Build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|\*\* BUILD" | sort -u
xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'platform=macOS' -derivedDataPath DerivedData/Build CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "error:|\*\* (BUILD|TEST)|failed" | sort -u
```

A failing test's message:

```sh
xcrun xcresulttool get test-results tests --path "$(ls -td DerivedData/Build/Logs/Test/*.xcresult | sed -n 1p)" --compact | jq -r '.. | objects | select(.result? == "Failed")'
```

- SourceKit's "Cannot find … in scope" / "No such module 'Testing'" diagnostics are noise; `xcodebuild` is the verifier.
- Never `screencapture` or drive the app on the owner's Mac. Agents on mini look at their own simulator instead (below). A visual question neither settles goes to the owner with exact steps.
- To settle a SwiftUI behaviour question (does it animate, what does it measure), a throwaway `swiftc` script hosting the view offscreen in an `NSHostingView` and comparing `cacheDisplay` bitmaps is allowed; delete it after.
- A docs-only change needs no build.

### Look at it (agents on mini)

Only in the simulator your assignment names. Take the before shot before you change anything.

```sh
SIM=<your simulator>
xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath DerivedData/Build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build 2>&1 | grep -E "error:|\*\* BUILD" | sort -u
xcrun simctl bootstatus "$SIM" -b
xcrun simctl install "$SIM" "DerivedData/Build/Build/Products/Debug-iphonesimulator/Dev Tools for Plex.app"
xcrun simctl launch --terminate-running-process "$SIM" mldgg.devtools
xcrun simctl io "$SIM" screenshot /tmp/<issue>-<what>.png   # once it has drawn; then look at the picture
```

- Variants: `xcrun simctl ui "$SIM" appearance dark`, `xcrun simctl ui "$SIM" content_size accessibility-extra-large`, `xcrun simctl ui "$SIM" increase_contrast enabled`.
- `simctl` can't tap, type or use the menu bar, and the simulator is an iPhone: anything past the launch screen, the iPad layout and the Mac app go to the owner as **Not checked**.
- `xcrun simctl shutdown "$SIM"` when you're done.

## 4. Pre-merge checklist

Walk `git diff origin/main...HEAD` (and `git diff` for anything uncommitted) against every line. Fix, don't note.

**Comments** — every comment in the diff, and on lines it touches, meets AGENTS.md's bar (a *why* the code can't carry, one or two sentences); delete the rest. The change shouldn't raise the app above about 20 comment lines per 1,000 lines of code.

**Tokens** — nothing new shows, copies, logs, or URL-encodes the app's tokens; they travel only as the `X-Plex-Token` header. A new `URLSession` that carries a token uses `SameOriginRedirects`; anything saved, copied, or exported from a request goes through `withoutCredentials`; artwork goes through `ImageStore`.

**Platform** — no raw `NS*`/`UI*` type in a feature file outside a view representable; differences go through `Core/Platform.swift`; `#if os` only for genuine layout differences. Monospace only via `Font.code` / `.codeListRow` / `.codeDetailRow`.

**Toolbar and menus**
- Placement per AGENTS.md: column → toolbar, object → request bar, sub-pane → its header row.
- Every toolbar command has a menu bar command in the right menu, dimmed (never removed) when unavailable. A new shortcut collides with nothing in `grep -rn keyboardShortcut DevTools` and doesn't repurpose a standard one.
- An item two sections share is declared once at the pane, never from inside a section's content. A view adds a `.toolbar` only where it declares items.
- Anything published to the window (toolbar items, `focusedSceneValue`) gates on `sectionIsActive`, since hidden sections stay mounted.

**Controls, states, copy**
- Icon-only controls are `Label` + `.labelStyle(.iconOnly)` + `.help`; decorative symbols `.accessibilityHidden(true)`; status colour always paired with words.
- Resting and empty-result states are `ZeroState`; failures and missing prerequisites are `ContentUnavailableView` saying what to do. Spinners unlabelled; nothing blocked while loading; disabled when there's no server.
- Title Case controls and menu items, sentence-case descriptions, verbs on buttons, `…` on commands that ask first. Only the actions AGENTS.md lists ask for confirmation.

**Motion**
- `.animation(_, value:)` scoped to the value; system springs (`.snappy`, `.smooth`, `.bouncy` only for a user-caused landing); a Reduce Motion variant; nothing ambient; no motion on the response body.
- Keyframes: `MoveKeyframe` for an instant jump (a zero-duration curve keyframe is NaN and hides the view), and end on the exact rest value.
- `ViewThatFits` draws its choice without content transitions; rolling numbers that shed by width use a `Layout` (see `SheddingRow`).
- Non-trivial motion has been through the `animate` and `review-animations` skills.

**Data and tests**
- Persistence goes through `AppSupportStore`, `Codable`, tolerant of old files (unknown keys ignored, new keys optional). A new store holding account or server state joins `SignOutConfirmation`'s teardown.
- A new contract (parsing, URL/string building, matching, redaction) gets a test that a plausible bug would fail. No plumbing tests; delete tests that pin wording or implementation.

**Docs** — a rule goes in AGENTS.md only if it's verified (not inferred), an agent couldn't see it from the code or the HIG, and breaking it costs something real (see AGENTS.md's opening). Narrow existing wording rather than adding lines; a rule a change proves wrong is fixed or deleted in the same pull request. No new docs files.

## 5. Commit and open a pull request

- Commit: one commit per coherent change. The subject is plain prose saying what changed, with no Conventional Commits prefix (`feat:`, `fix:`); the body says why, and records the constraint behind any non-obvious choice.
- For a non-trivial change, spawn a `reviewer` agent on `git diff origin/main...HEAD` with AGENTS.md as the bar; fix what it finds that holds up. Agents started by `work-issue` skip this: the coordinator starts a separate reviewer on the pull request.
- Push the branch (`git push -u origin <branch>`; outside an `issue-*` branch, only once the owner says so) and open a pull request. Its title is the release-note line: a user-facing summary in sentence case. Its body follows the PR template under "Writing for GitHub" in the user-level `work-issue` skill, with the checks line from `.agents/workflow.md`; never `gh pr create --fill`.
- Leave the branch checked out, so a Run in Xcode includes it. Tell the owner exactly what to look at (screen, action, expected result), and that `main` won't have it until it's merged. Ask to merge.

## 6. Merge on approval

Only when the owner says so (a `work-issue` reviewer queues the merge itself, per its brief):

```sh
gh pr merge <pr> --merge --subject "Merge: <the PR title, first letter lowercased>"
git switch main && git pull -q --ff-only
git branch -d <branch>            # every branch of a stack
```

Never squash or rebase a pull request: the release notes are read from merge commits.

The merge subject of a change to the app is a release-note line. `Tools/release.sh` builds a tag's notes from the merges on `main`'s first-parent line since the previous tag that touched `DevTools/`, strips `Merge: ` and capitalizes the first letter, so write it as a user-facing summary of the change.

A merged change isn't in the live DMG until a release (`release-workflow`); say so when it matters.
