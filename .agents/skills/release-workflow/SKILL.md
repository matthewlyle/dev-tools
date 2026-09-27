---
name: release-workflow
description: Cutting a release of the dev-tools Mac app — version bump, notarized DMG via Tools/release.sh, tag, landing-page update, Vercel deploy, and live verification. Use when asked to release, ship, make a new build, or put a new DMG on the website. TestFlight uploads are a separate step at the end.
---

# Cutting a release

`Tools/release.sh` does the building, notarizing, publishing into `site/`, and tagging. Around it: get `main` ready, bump the version, then commit the site change, deploy, verify, and push.

## Prerequisites (on this Mac)

- `Developer ID Application: Matthew Dunn (LQ2SFRWR75)` in the keychain: `security find-identity -v -p codesigning`
- notarytool credentials under the `notary` profile: `xcrun notarytool history --keychain-profile notary`
- The Vercel CLI signed in (`vercel whoami`), with `site/.vercel/project.json` linking project `plex-dev-tools`. `site/.vercel` is gitignored, so a fresh checkout or worktree needs it copied in.

## 1. Ready main

- Everything shipping is merged through `change-workflow`. `git switch main && git status -sb` shows a clean tree. The script refuses to start otherwise, because the tag must name exactly what was built.
- Ask before pushing any commits on `main` you didn't make.

## 2. Bump the version

- `MARKETING_VERSION` goes up every release: the DMG is named from it, and the tag `v<version>` must not already exist (`git tag`). `CURRENT_PROJECT_VERSION` goes up by one. Both appear four times in `DevTools.xcodeproj/project.pbxproj`; replace all.
- Bump on a `release-<version>` branch through `change-workflow`, or inside the last change's branch. Either is fine: the tag's notes list only merges that changed `DevTools/`, so neither the bump (which touches only `project.pbxproj`) nor the site commit shows up as a change.
- Build and test before merging the bump, as for any change.

## 3. Run the release

```sh
Tools/release.sh 2>&1 | grep -E "status: |: accepted|rejected|Invalid|rror|already tagged|uncommitted|wrote |^- |Next:"
```

- It takes a couple of minutes (two notarizations). Run it async and don't touch the tree until it finishes.
- Success is `…/Dev Tools for Plex.app: accepted`, `…/DevToolsForPlex-<version>.dmg: accepted`, and `wrote … and tagged v<version>:` followed by the notes.
- It leaves `site/DevToolsForPlex-<version>.dmg` (gitignored), deletes older DMGs from `site/`, and edits the download link and version line in `site/index.html`.
- `SKIP_NOTARIZE=1` builds and signs only, for a local check. It leaves `site/` and the tags alone, and its DMG can't be distributed.
- Never create or move a tag by hand to cover a failed run. Fix the cause and run again.

## 4. Publish

1. Commit `site/index.html` on a `site-<version>` branch and merge it into `main` (`change-workflow` step 6; no build needed).
2. Deploy from a checkout of `main`: `cd site && vercel deploy --prod --yes`. If the working checkout is on another branch with its own `site/` edits, deploy from a worktree of `main` instead, with `site/.vercel` and the DMG copied in, so unmerged site changes don't go live.
3. Verify the live site:

```sh
B=https://plex-dev-tools.vercel.app
curl -s -o /tmp/live.dmg -w "HTTP %{http_code}\n" $B/DevToolsForPlex-<version>.dmg
[ "$(shasum -a 256 < /tmp/live.dmg)" = "$(shasum -a 256 < build/release/DevToolsForPlex-<version>.dmg)" ] && echo "matches notarized build"
curl -s $B/ | grep -oE 'href="DevTools[^"]*"|Version [0-9.]+'
curl -s -o /dev/null -w "previous DMG: HTTP %{http_code}\n" $B/DevToolsForPlex-<previous>.dmg   # expect 404
```

4. Push the branch and the tag together: `GIT_TERMINAL_PROMPT=0 git push -q origin main v<version>`, then check `git ls-remote --tags origin | grep v<version>`.

## 5. Report

The version and build, notarization accepted, the live URL, that the live file matches the build, and the tag's notes (`git show v<version>`).

## TestFlight (only when asked)

`Tools/upload-ios.sh` archives the iOS app and uploads it to App Store Connect. It raises the build number itself, and it needs the `mldgg.devtools` app record to exist in App Store Connect.
