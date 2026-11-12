# dev-tools: agent workflow

What the shared `work-issue` and `github-issue` skills (`skills/` in `matthewlyle/tracker`) need
to know about this repo. The process lives there; only what's specific to dev-tools lives here.
Building, verifying, looking at a change and the pre-merge checklist are in
`.agents/skills/change-workflow/SKILL.md`; workers follow it and reviewers walk its checklist line
by line.

## Repo

- GitHub `matthewlyle/dev-tools`, owned by `matthewlyle`; checkout `~/src/dev-tools`; worktrees under
  `~/.herdr/worktrees/dev-tools/`. Agents run on mini. Releases don't: they need the Developer ID
  identity, the notary profile and Vercel, which live on the owner's Mac (`release-workflow`).
- `~/src/dev-tools` is the owner's checkout: agents only `git fetch` and `git worktree add` there,
  and never check out, pull, commit or edit it. Work happens in their own worktree.

## Per issue

- Each agent gets its own iPhone simulator, cloned from `devtools-base`: `devtools-<n>` for the
  worker (`xcrun simctl clone devtools-base devtools-<n>`), `devtools-<n>-review` for the
  reviewer, reused by every review of that PR. `devtools-base` is signed in to Plex by the owner,
  and a clone carries the sign-in. It must be shut down to clone. If it's missing, stop and ask
  the owner: agents can't sign in.
- Worker task: `Issue <n>, simulator devtools-<n>.` Reviewer task:
  `PR <pr>, issue <n>, simulator devtools-<n>-review.`
- An agent uses only its own simulator, only through `xcrun simctl` (change-workflow, "Look at
  it"). Never `screencapture`, never launch the Mac app, never touch another simulator.
- Lite fits a one-line copy or constant fix, not layout or concurrency work.
- A change to `AGENTS.md` or `.agents/` is never lite: it goes to the owner as Human.

## Milestone

- One PR per milestone, as `work-issue`'s `milestones.md` describes. Each issue's worker keeps its
  own simulator; the PR's reviewer takes `devtools-<a>-review` (the first issue's number), with
  task `PR <pr>, issues <a>, <b>, <c>, simulator devtools-<a>-review.`
- Milestone merge: `gh pr merge <pr> -R matthewlyle/dev-tools --auto --rebase` (keeps one commit
  per issue, and the release notes then list each issue's commit subject). Never squash a
  milestone PR.

## Build, check, look

- Verify: both change-workflow verify commands print SUCCEEDED and its pre-merge checklist
  passes. The PR's required check is `build-test`.
- Look: change-workflow, "Look at it".
- Agents can't check what needs a tap, typing or the menu bar (`simctl` can launch and
  screenshot, nothing more), the Mac app, or a device.
- Checks line: `iOS Simulator build, macOS tests, pre-merge checklist`.

## Commits, PRs, merging

- Commit per change-workflow: a plain-prose subject saying what changed (no `feat:`/`fix:`
  prefix); the body says why.
- PR title: the release-note line, a user-facing summary in sentence case. **Try it** names the
  platform, screen and action.
- Merge: `gh pr merge <pr> -R matthewlyle/dev-tools --auto --merge --subject "Merge: <the PR title, first letter lowercased>"`.
  The merge subject becomes a line in the release notes (`Tools/release.sh`).
- A PR that conflicts with `main` only because another PR touched the same lines is the
  reviewer's to fix: merge `origin/main` into the branch, keep both sides, re-run the verify steps
  and push. Any other conflict is a Fix.
- Off limits: `Tools/release.sh`, `site/`, the version numbers.

## Deploy

- Nothing to deploy: merging ships nothing. The notarized DMG and the TestFlight build come from
  `release-workflow`, run by the owner.

## Cleanup

- `xcrun simctl delete devtools-<n> devtools-<n>-review`.

## Issues

- Areas: a section (Endpoints, History, Activity, Media), Settings, Sign-in, or `App-wide`.
  Examples: `Activity: connection capsule covers the last event on iPad`,
  `App-wide: icon-only toolbar buttons have no VoiceOver label`.
- Where: `` - Mac | iPad | iPhone — Section › element — `DevTools/path/File.swift:123` ``.
- Steps start from a fresh launch, signed in, with a server selected, and name the input method
  (pointer, keyboard, touch, VoiceOver) and the width (regular, compact) where it matters.
- Criteria like "⌘L focuses the path field", "the row wraps at 360 pt".
- Reference: an HIG page or API doc; optional.
- Reproduced label: `verified: app` (Mac, simulator or device).
- Screenshots come from a simulator (`xcrun simctl io <sim> screenshot`), never the owner's screen.
