---
name: change-workflow
description: The workflow for every change to the dev-tools app (a fix, a feature, a refactor, a doc edit) from branch to merged and pushed. Use for any task that edits the repo; ends with a pre-merge checklist distilled from AGENTS.md. Not for releases (release-workflow).
---

# Making a change

Branch, do the work, verify, check, commit, hand off for review, merge on approval. `AGENTS.md` holds the rules; this is the order they're applied in and the checks that catch what slips on every merge.

## 1. Start

- `git switch main && git status -sb` — expect a clean tree and `## main...origin/main`. Commits on `main` you didn't make are the user's: leave them, and ask before pushing any that aren't on `origin` yet.
- `git switch -c <short-kebab-name>`. Never commit on `main` or on a branch you didn't create.
- Building on an unmerged branch of yours? Branch from it instead (stacked) and say so; merging the top merges them all.

## 2. Work

Read the `AGENTS.md` sections the change touches before editing. Reuse the existing pattern; a second convention beside it is a bug. Unmerged commits on your own branch can be amended; merged ones never.

## 3. Verify

Both must print SUCCEEDED before a commit. Gate the commit on them (`&&` or an explicit check) — a `;` chain commits over a failed test.

```sh
xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/Build build 2>&1 | grep -E "error:|\*\* BUILD" | sort -u
xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'platform=macOS' -derivedDataPath DerivedData/Build test 2>&1 | grep -E "error:|\*\* (BUILD|TEST)|failed" | sort -u
```

A failing test's message:

```sh
xcrun xcresulttool get test-results tests --path "$(ls -td DerivedData/Build/Logs/Test/*.xcresult | sed -n 1p)" --compact | jq -r '.. | objects | select(.result? == "Failed")'
```

- SourceKit's "Cannot find … in scope" / "No such module 'Testing'" diagnostics are noise; `xcodebuild` is the verifier.
- Never screenshot, `screencapture`, or drive the running app. A visual question you can't settle from code goes to the user with exact steps.
- To settle a SwiftUI behaviour question (does it animate, what does it measure), a throwaway `swiftc` script hosting the view offscreen in an `NSHostingView` and comparing `cacheDisplay` bitmaps is allowed; delete it after.
- A docs-only change needs no build.

## 4. Pre-merge checklist

Walk `git diff main...HEAD` (and `git diff` for anything uncommitted) against every line. Fix, don't note.

**Comments** — delete any that:
- restate the code, name the type, or narrate steps;
- are `// MARK:`, TODOs, or doc comments a signature already says;
- describe what a view shows or how a feature behaves, or document wiring (`Published by…`, `Set by…`);
- repeat AGENTS.md;
- carry an anecdote: counts, timings, specific values met, "this showed up as", "we would have missed". The story goes in the commit message.

Keep only an external constraint and what it forces, a deliberate policy that looks like an omission, or a non-obvious invariant, in one or two sentences. Comments on lines you touched that fail this bar go too. The change shouldn't raise the app above about 20 comment lines per 1,000 lines of code.

**Tokens** — nothing new shows, copies, logs, or URL-encodes a credential; `X-Plex-Token` travels only as a header; artwork goes through `ImageStore`.

**Platform** — no raw `NS*`/`UI*` type in a feature file; differences go through `Core/Platform.swift`; `#if os` only for genuine layout differences. Monospace only via `Font.code` / `.codeListRow` / `.codeDetailRow`.

**Toolbar and menus**
- Placement per AGENTS.md: column → toolbar, object → request bar, sub-pane → its header row.
- Every toolbar command has a menu bar command in the right menu, dimmed (never removed) when unavailable. A new shortcut is added to AGENTS.md's list and doesn't repurpose a standard one.
- A detail toolbar item is declared at the pane with a stable `ToolbarItem(id:)`, never from inside a section's content. A view adds a `.toolbar` only where it declares items.
- Anything published to the window (toolbar items, `focusedSceneValue`) gates on `sectionIsActive`, since hidden sections stay mounted.

**Controls, states, copy**
- Icon-only controls are `Label` + `.labelStyle(.iconOnly)` + `.help`; decorative symbols `.accessibilityHidden(true)`; status colour always paired with words.
- Resting and empty-result states are `ZeroState`; failures and missing prerequisites are `ContentUnavailableView` saying what to do. Spinners unlabelled; nothing blocked while loading; disabled when there's no server.
- Title Case controls and menu items, sentence-case descriptions, verbs on buttons, `…` on commands that ask first. Un-undoable destructive actions confirm.

**Motion**
- `.animation(_, value:)` scoped to the value; system springs (`.snappy`, `.smooth`, `.bouncy` only for a user-caused landing); a Reduce Motion variant; nothing ambient; no motion on the response body.
- Keyframes: `MoveKeyframe` for an instant jump (a zero-duration curve keyframe is NaN and hides the view), and end on the exact rest value.
- `ViewThatFits` draws its choice without content transitions; rolling numbers that shed by width use a `Layout` (see `SheddingRow`).
- Non-trivial motion has been through the `animate` and `review-animations` skills.

**Data and tests**
- Persistence goes through `AppSupportStore`, `Codable`, tolerant of old files (unknown keys ignored, new keys optional).
- A new contract (parsing, URL/string building, matching, redaction) gets a test that a plausible bug would fail. No plumbing tests; delete tests that pin wording or implementation.

**Docs** — a new load-bearing decision goes in AGENTS.md by narrowing the existing wording, not by adding lines. No new docs files.

## 5. Review

- For a non-trivial change, spawn a `reviewer` agent on `git diff main...HEAD` with AGENTS.md as the bar; fix what it finds that holds up.
- Commit: one commit per coherent change. The subject is plain prose saying what changed, with no Conventional Commits prefix (`feat:`, `fix:`); the body says why, and records the constraint behind any non-obvious choice.
- Leave the branch checked out, so a Run in Xcode includes it. Tell the user exactly what to look at (screen, action, expected result), and that `main` won't have it until it's merged. Ask to merge.

## 6. Merge on approval

Only when the user says so:

```sh
git switch main && git merge --no-ff -q <branch> -m "Merge: <what, lowercase>"
# re-run both verify commands; both must succeed
git branch -d <branch>            # every branch of a stack
GIT_TERMINAL_PROMPT=0 git push -q origin main
git status -sb | sed -n 1p        # expect ## main...origin/main
```

The merge subject of a change to the app is a release-note line. `Tools/release.sh` builds a tag's notes from the merges on `main`'s first-parent line since the previous tag that touched `DevTools/`, strips `Merge: ` and capitalizes the first letter, so write it as a user-facing summary of the change.

A merged change isn't in the live DMG until a release (`release-workflow`); say so when it matters.
