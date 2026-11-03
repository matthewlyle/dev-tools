---
name: github-issue
description: Writing and filing GitHub issues for dev-tools with gh, including the body structure, titles, grouping, labels, and duplicate checks.
---

# Writing a GitHub issue

Issues go to `matthewlyle/dev-tools` on GitHub; pass `-R matthewlyle/dev-tools` to every `gh` command.

## Before filing

- Collect every finding first and show the user the list (title and a one-line summary each). Don't file until they approve. They may cut, merge or reword findings.
- Check for duplicates: `gh issue list -R matthewlyle/dev-tools --state all --search "<keywords>"`. If a match is open, tell the user and don't file a second one.
- Group by problem, not by place. When the same problem shows up in several places, file one issue and list every location. Split only when the fixes are unrelated. Each issue should be one release-note line and one reviewable PR.
- Every issue gets `agent`, a topic label (such as `accessibility`) and one `severity: <level>` label matching the body's severity. A bug (something broken that can be reproduced) also gets one verification label; feature requests and `enhancement` issues get none:
  - `verified: app`: reproduced in the running app (Mac, simulator or device).
  - `verified: code`: found by reading code and not yet reproduced.
- Add `review: design` when the fix changes how the app looks or needs a UX decision. Mark real ordering between issues with issue dependencies (`gh api -X POST repos/matthewlyle/dev-tools/issues/<n>/dependencies/blocked_by -F issue_id=<database id>`).
- Use labels that already exist (`gh label list -R matthewlyle/dev-tools`). Don't create other labels unless the user asks.

## Title

`<Area>: <problem>`, in sentence case, with no trailing period. Name the problem, not the fix. The area is a section (Endpoints, History, Activity, Media), Settings, Sign-in, or `App-wide` when the problem shows up in several.

- `Activity: connection capsule covers the last event on iPad`
- `App-wide: icon-only toolbar buttons have no VoiceOver label`

## Body

Use these sections in this order. Omit a section only if it says it's optional. Keep every section short: fragments are fine, one line per item, no narration or hedging. Description and Actual are one or two sentences each; aim for under about 150 words before Reference.

```markdown
## Description
One or two sentences: what's wrong and who it affects.

**Severity:** blocker | serious | moderate | minor

## Where
- Mac | iPad | iPhone — Section › element — `DevTools/path/File.swift:123`
- one line per location

## Steps to reproduce
1. Concrete, numbered steps from a fresh launch, signed in, with a server selected.
2. Include the input method (pointer, keyboard, touch, VoiceOver) and the width (regular, compact) where it matters.

## Expected
What should happen.

## Actual
What happens now. Quote exact output, announcements, or values where there are any.

## Success criteria
- [ ] A checkable statement someone can verify by doing it, such as "⌘L focuses the path field" or "the row wraps at 360 pt".
- [ ] One checkbox per location, platform or behavior when there are several.

## Reference
[HIG page or API doc](https://link) — what defines the expected behavior. Optional.
```

The success criteria have to be testable. "Is accessible" or "works correctly" isn't a criterion; "VoiceOver reads 'Send, button'" is. Say which platform each criterion is on when they differ.

Screenshots: if the problem was confirmed by looking at it, add an `**Evidence**` block at the end of Actual. `gh` can't upload images. Commit PNGs to the orphan `issue-assets` branch under `<topic>/<issue>-<what>.png`, push only with the user's OK, and link them as `https://raw.githubusercontent.com/matthewlyle/dev-tools/issue-assets/<topic>/<file>.png`. Never screenshot the owner's screen: simulator screenshots only (`xcrun simctl io <sim> screenshot`).

Severity:

- blocker: the task can't be done at all.
- serious: the task can be done, but only with real difficulty or a workaround.
- moderate: the task is noticeably degraded.
- minor: polish.

## Filing

Don't hard-wrap prose: GitHub turns every newline in an issue, PR or comment body into a line break. Write one line per paragraph or list item.

Write the body to a file so Markdown doesn't get mangled by shell quoting:

```sh
gh issue create -R matthewlyle/dev-tools \
  --title "Area: problem" \
  --label agent --label <topic> --label "severity: <level>" [--label "verified: <app|code>"] \
  --body-file /tmp/issue-<slug>.md
```

When filing a batch, file them one at a time, collect each URL `gh` prints, and report all the URLs to the user at the end. Delete the temp body files afterwards.
