---
name: work-issue
description: Fanning dev-tools GitHub issues out to omp worker agents on mini, one worktree, simulator and PR per issue.
---

# Working issues with worker agents

One issue, one worktree, one simulator, one omp agent, one PR. Follows `change-workflow`: branch `issue-<n>-<slug>`, PR title is the release-note line, body says `Fixes #<n>`. Workers never merge; only the reviewer, or the lead once the owner adds `approved`, may queue a merge.

Agents run on mini, from `~/src/dev-tools`. Releases don't: they need the Developer ID identity, the notary profile and Vercel, which live on the owner's Mac (`release-workflow`).

## Check for existing work

Before launching, look for an earlier attempt: `git -C ~/src/dev-tools worktree list` and `gh pr list -R matthewlyle/dev-tools --state all --search "<n> in:body"`. A branch, worktree or PR may already exist. An open PR whose head matches the worktree's HEAD goes straight to review; an unpushed worktree gets a worker in that worktree.

## Launch a worker

Start workers and reviewers with the `herdr-workers` skill (user-level, from `matthewlyle/agent-skills`, not this repo). It covers `hc`, the Herdr app, templates and how agents report back; this repo's `.agents/templates/` says what each agent does, with its brief in `.agents/prompts/`. Each issue gets its own tab: the worker and, later, its reviewer.

The templates are linked into hc as `dev-tools-<role>`, once per machine (see "Templates" in `herdr-workers`). The links point into `~/src/dev-tools`, so a template's model changes when that checkout is on the new `main`; a brief changes with `.agents/prompts/` on the agent's own branch.

```sh
git -C ~/src/dev-tools fetch origin main
git -C ~/src/dev-tools worktree add ~/.herdr/worktrees/dev-tools/issue-<n>-<slug> -b issue-<n>-<slug> origin/main
xcrun simctl clone devtools-base devtools-<n>
```

`devtools-base` is an iPhone simulator the owner signed in to Plex once; a clone carries that sign-in. It must be shut down to clone. If it's missing, stop and ask the owner: agents can't sign in.

Then start the worker with `herdr-workers`: name `<n>-<what it fixes>` (`9-wrap-long-headers`, not `issue-9`), folder the worktree, label `issue=<n>`, a template from the table below, and the task `Issue <n>, simulator devtools-<n>.` Tell the owner to name the issue's tab `#<n> <short title>`.

Pick the cheapest template that fits; the reviewer catches mistakes:

| Job | Template |
|---|---|
| Worker, normal fix | `dev-tools-worker` (Sonnet) |
| Worker, one-line copy or constant fix | `dev-tools-worker-lite` (Haiku: 100K context; not for layout or concurrency work) |
| Text or mechanical follow-up (trim a PR body, merge `main`) | none: `omp --model claude-haiku-5-5` with the instructions as its prompt |
| Reviewer | `dev-tools-reviewer` (Opus, thinking low) |

If a cheaper worker's PRs keep bouncing in review, move that kind of issue up a tier.

## Review each PR

When a worker reports its PR, clone a second simulator (`xcrun simctl clone devtools-base devtools-<n>-review`) and start a reviewer (a different agent from the worker) with `herdr-workers` in the issue's tab: name `<n>-review`, folder the worktree, label `issue=<n>`, template `dev-tools-reviewer`, and the task `PR <pr>, issue <n>, simulator devtools-<n>-review.`

The reviewer reports Merge, Fix or Human:

- **Fix:** send the review's **Fix before merge** list to the worker (`hc send <n>-<slug> …`). When it reports the new head, end the old `<n>-review` and start a fresh one on that head with the same simulator. A third review that still finds fixes goes to the owner.
- **Human:** the owner answers on the PR or issue, or adds `approved`, which means yes to every **Your call** question. Have the worker make any listed fixes, then, once CI passes on the new head, queue the merge yourself (`gh pr merge <pr> -R matthewlyle/dev-tools --auto --merge --subject "Merge: <the PR title, first letter lowercased>"`), in dependency order when PRs build on each other.

## Writing for GitHub

The owner reads these on a phone between other work. Be terse: fragments are fine, no narration of how you worked, no restating the issue, no hedging. One line per paragraph or list item (GitHub turns newlines into line breaks). Numbers and names over adjectives.

Use GitHub callouts (`> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`) for what the owner must see, and fold the evidence into `<details>`. Keep a blank line before and after every callout, list and `<details>` block, or GitHub merges them.

PR body, at most about 100 words outside the screenshots and the folded checks:

```markdown
Fixes #N

<One or two sentences: what changed, in user terms. Plain text, no callout.>

**Try it:** <one line: platform, screen, action>

<before/after screenshot table, if anything visible changed or must look unchanged>

<details>
<summary>Checked: <count> passed</summary>

- <criterion 1>
- <criterion 2>
- iOS Simulator build, macOS tests, pre-merge checklist

</details>
```

Callouts in a PR body are only for something that needs attention: a `> [!WARNING]` with **Not checked:** before `<details>`. The description itself is never in a callout.

Review comment, merge:

```markdown
> [!TIP]
> **Merging** once checks pass. Nothing needs you.

<details>
<summary>Checked: <count> passed</summary>

- <criterion>
- Diff in scope; builds, tests, checklist, CI

</details>

<sub>Agent review of <short sha></sub>
```

Review comment, back to the worker (no label, no assignee):

```markdown
> [!WARNING]
> **Fix before merge**
> - <bug, with file and numbers>

<details>
<summary>Checked: <count> passed</summary>

- <criterion>
- Builds, tests, checklist, CI

</details>

<sub>Agent review of <short sha></sub>
```

Review comment, needs a person (at most about 60 words outside `<details>`):

```markdown
> [!IMPORTANT]
> **Your call:** <the one question>
>
> <one or two lines of context, with numbers>

> [!WARNING]
> **Fix before merge**
> - <bug, with file and numbers>

<details>
<summary>Checked: <count> passed</summary>

- <criterion>
- Builds, tests, checklist, CI

</details>

<sub>Agent review of <short sha></sub>
```

Omit the WARNING when there's nothing to fix. If a person is needed only for something you couldn't check, say that under **Your call**. Several questions: one bullet each inside the IMPORTANT box.

Merging to `main` doesn't ship anything: the DMG and TestFlight builds come from `release-workflow`. After a PR merges, end its agents (`<n>-<slug>`, `<n>-review`), delete their simulators (`xcrun simctl delete devtools-<n> devtools-<n>-review`), and remove the worktree (`git -C ~/src/dev-tools worktree remove <path>`, then delete the local branch).

## Coordinator checklist

- Before launching, read the issue's comments as well as its body: the owner answers design questions there. Copy each answer into the issue as a `## Decision` section.
- When a worker reports done, check `gh pr view <pr> -R matthewlyle/dev-tools --json headRefOid` against its local HEAD. Agents have reported pushes that never happened. Start a reviewer only on the pushed head.
- After a merge, merge `main` into open PRs that touch the same files before their review.
- Before starting new work, check `gh pr list -R matthewlyle/dev-tools --label approved` and queue the merges those are waiting on.
