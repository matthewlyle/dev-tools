Review pull request #{PR} in matthewlyle/dev-tools, which claims to fix issue #{N}. Read `gh issue view {N}`, `gh pr view {PR}` and `gh pr diff {PR}` (each with `-R matthewlyle/dev-tools`). Follow AGENTS.md. You're explicitly asked to post one GitHub review and to label or queue a merge as described below; nothing else on GitHub.

Check, and re-run what you can rather than trusting the PR body:
- Every success criterion in the issue is met. Build the branch and look at it in your simulator `{SIM}` (change-workflow, "Look at it"); compare with the PR's screenshots. `simctl` can't tap, type or use the menu bar, so a criterion that needs that, the Mac app or a device goes to a person. For a CI change, check real Actions runs (`gh run list`, `gh run view --log`).
- A criterion that needs a repository setting (rulesets, required checks) can't be met by the PR. Don't change settings; put it under **Your call**.
- The diff stays within the issue, passes the pre-merge checklist in `.agents/skills/change-workflow/SKILL.md` line by line, and has no dead code, comments that fail AGENTS.md's bar, or unrelated changes.
- Both change-workflow verify commands print SUCCEEDED, and the `build-test` check on the PR passed.
- The PR title is a user-facing release-note line, and the body follows the template in "Writing for GitHub" with screenshots if anything visible changed.

Then decide:
- Merge: the issue has no `review: design` label, you found nothing that needs fixing, every criterion checked out, and nothing visible changed. Post a comment review (`gh pr review {PR} --comment`) using the merge template, then `gh pr merge {PR} -R matthewlyle/dev-tools --auto --merge --subject "Merge: <the PR title, first letter lowercased>"`. GitHub merges only once the required checks pass. The merge subject becomes a line in the release notes (`Tools/release.sh`), so never merge another way. (Agents use the owner's account, which can't approve its own PRs, so the review is a comment.)
- Human: anything else, including anything you couldn't check. Post a comment review using the human template, then `gh pr edit {PR} -R matthewlyle/dev-tools --add-label "review: human" --add-assignee matthewlyle`.
- Never request changes from the worker, push to the branch, or merge directly.

Write the review with the templates in `.agents/skills/work-issue/SKILL.md` under "Writing for GitHub". Finish with a short report: the decision, why, and the review URL.
