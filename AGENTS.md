# Agent rules for dev-tools

Native SwiftUI app for macOS 26, iPadOS 26, and iOS 26: a Plex Media Server API playground. These are the rules that aren't obvious from the code. Each one is here because breaking it leaks a credential, breaks a published promise, stalls or loops the UI, or starts a second convention. Follow Apple's Human Interface Guidelines for the rest; when in doubt, read the HIG page, not another app.

## Comments: almost never

Default to none. A comment is one or two sentences of *why* the code can't carry: an external constraint (a Plex quirk, a HIG rule, a framework limitation, a performance cliff) and what it forces, a deliberate policy that looks like an omission, or a non-obvious invariant. Never restate or narrate the code, describe what the user sees or how things are wired, `// MARK:`, TODOs, repeat this file, or tell how the constraint was found: that story goes in the commit message. Budget: about 20 comment lines per 1,000 lines of code; when you touch a file, delete comments that fail this bar.

## Credentials and privacy

`site/privacy.html` publishes these promises; breaking one breaks it.

- **The app's tokens are never shown, kept outside the Keychain, or put in a URL.** They travel only in the `X-Plex-Token` header, the notification WebSocket included. The account token lives in the data protection keychain as an `…ThisDeviceOnly` item; server tokens are never persisted and come back with each `/api/v2/resources` refresh. No reveal, toggle, or query-string option. Anything that shows or copies server text takes it through `CredentialRedactor`; a new view reads the redacted response, never a raw `PlexHTTP.send` body.
- **Artwork loads only through `ImageStore`, never `AsyncImage`**, which caches to disk (`URLCache.shared`); artwork stays in memory.
- **The token goes only to a server that proved itself over TLS.** Probes hit `/identity` without it, and plain HTTP is never probed, whatever `httpsRequired` says. Don't add an insecure-connections option: people locked out fix the server or router. URLSession forwards custom headers like `X-Plex-Token` to any redirect target (it drops only `Authorization`), so every session that carries a token uses `SameOriginRedirects`.
- **A token typed into a request is sent but never kept or handed out.** Anything saved, copied, or exported from a request, saved names included, goes through `PlexRequest.withoutCredentials`, so a replay goes out with the server's own token.
- **Sign-out goes only through `SignOutConfirmation`**, which tears down every store holding account or server state itself, since the views are unmounted before their `onChange`s could run. A new such store joins that teardown, and its async loads check a generation after each await (as `ServerStore.generation` does) so a late answer can't refill it for the next account.

## Structure

- **The server is the scope, picked from the window title's menu (`ServerMenu`).** No servers sidebar or Servers tab, and nothing else in the header: the account and Settings live in Settings and the menu bar (on iOS, Settings… ends the title menu). Saved requests are a pinned group in the endpoint list, not a section.
- **One header over the whole window:** server title leading, section switcher centred via `.secondaryAction`, section actions trailing. On iPad that's one `NavigationStack` bar over `ListDetailPanes` with `.toolbarRole(.editor)`: a `NavigationSplitView` gives each column its own bar, the default role sends `.secondaryAction` to the overflow menu, and `.principal` replaces the title. A list's filter and its sort/clear go through `listFilter` (`actions:`), never `.searchable` or `.sectionListToolbar` directly.
- **All four sections stay mounted; the switcher only changes which is visible** (`sectionResident(active:)`), so a switch never rebuilds one. Anything a section publishes to the window (`.sectionListToolbar` items, `.focusedSceneValue`) gates on `@Environment(\.sectionIsActive)`, or menu commands act on a section that isn't showing. The section changes only through `MainSplitView`'s `sectionBinding`, which parks the outgoing section's request and response (`switchWorkspace`). A section never declares its own `.inspector`: the detail pane hosts one, `SectionInspector`, showing what the visible section has open from that section's store.
- **A section's list pane only filters or chooses what the detail shows.** Status and controls for the detail's content (`ActivityConnectionControl`) live with the detail, and reactions to a server switch live in `MainSplitView`, since a list pane isn't mounted on every layout.
- **Every platform difference goes through `Core/Platform.swift`** (`PlatformImage`, `PlatformFont`, `PlatformColor`, `Clipboard`): no raw `NS*`/`UI*` type in a feature file outside a view representable, and `#if os` only for genuine layout differences.
- **Response format (`Accept`) is an app-wide setting**, not per request; replays use the current setting.
- **Notifications are WebSocket-only, at `/:/websockets/notifications` (plural).** The singular path in Plex's spec 404s.
- **`DevTools/Resources/plex-openapi.json` is generated** by `Tools/extract-spec.sh`. Never hand-edit it; fix consumers instead. The spec is a guide, not truth: it often omits `required`, so nothing blocks sending a request the spec calls incomplete, and users can type any parameter.

## Layout

- **Nothing in the detail may need more than about 360 pt.** A wider minimum sends the macOS split view into a layout loop (an exception on macOS 26), so a row of fixed-size controls wraps (`InfoRowLayout`). Lists use two-line rows, not tables.
- **Large bodies:** above 256 KB the body is always wrapped (`BodyControls.wrapForcedAbove`), and JSON is pretty-printed even above `ResponseDocument.highlightLimit`. Unwrapped text, or one multi-MB line, lays the whole document out on the main thread. Don't relax either. The body's `CodeTextView` is always its own scroller, never inside a page `ScrollView` (sizing it there lays out the whole document); content that scrolls with it goes in `CodeTextView(header:)`.
- No auxiliary windows. A sheet is a `SheetScaffold`; a popover that can become a sheet on iPhone takes an ideal width, never a fixed one.

## Toolbar and menus

- **Placement.** Toolbar: what acts on the column (switch, sort, clear) and on the request as a whole (docs, copy, save: `RequestToolbarItems`). Request bar: what edits or sends the request; it stays `GET [path] [Send]`. A sub-pane's header row: what acts on that pane (wrap, fold, copy body). At most one segmented control, no status text, and nothing that repeats the server name the title already shows. Rare actions like Refresh Servers get no toolbar button.
- **An item two sections share is declared once at the pane**, never per section or inside a section's content. Adding or removing toolbar items crossfades the whole macOS toolbar, so a change that does it goes through `withoutToolbarFade` (the section switch already does). Dim a temporarily unavailable item rather than removing it; at most three trailing items.
- **Every toolbar or context command also has a menu bar item**; only the section switcher and the compact tab bar are exempt. App commands go in **Server** (the selected server) or **Request** (the request in the bar) in `AppCommands.swift`, never a third menu, with no menu item icons. A command on the visible section reads a `FocusedValues` action and is disabled when it's nil.
- **Shortcuts** only for frequent commands. Before adding one, check `grep -rn keyboardShortcut DevTools` for a collision, and never repurpose a standard one.

## Controls and visuals

- **Never apply `glassEffect` yourself.** Glass is the system's bars, tab bar accessory, and `.glassProminent` Send; content panes use `.fill.tertiary`/`.quaternary`. The one exception is Activity's connection capsule on iPad and the Mac: a control floating over content with no system home. A second needs the same case.
- **The detail well (`WellBackground`) is the one translucent content surface**; don't add behind-window vibrancy elsewhere. On iOS one well backs every screen and spans both iPad panes, so nothing on it gets an opaque fill: the code surface is `.clear`, and an opaque one shows as a black slab.
- **A resting or empty-result state** (nothing sent or queried yet, not connected, no events, no matches) is `ZeroState`: one sentence, no button. A failure or missing prerequisite is `ContentUnavailableView` saying what to do next. Spinners are unlabelled and never block the view: the last response stays readable while sending, and what needs a server is disabled without one.
- Only Clear History, Sign Out, and deleting a saved request ask first; Disconnect, Clear Events, and deleting a history item don't.
- Icon-only buttons are `Label("Verb", systemImage:)` + `.labelStyle(.iconOnly)` + `.help`, never a bare `Image`; decorative symbols are `.accessibilityHidden(true)`; a status colour always comes with words.
- **A selectable `List` row opens through `.contextMenu(forSelectionType:menu:primaryAction:)`**, never a tap gesture or row `Button`: on macOS those take the click from the table, so the row doesn't select. On a compact width taps neither select nor run the primary action, so there rows are `Button`s that set the selection.
- A field taking epoch seconds gets `EpochDateButton` and an `EpochReadout`; `EpochDate.isEpochName` decides which names are dates everywhere.
- **Colour.** System colours only; anything hashed to a colour indexes the 12-colour system palette (`ActivityFiltersView`), never a raw hue. Code-surface colours come from `CodeColors.system`: a new token is a `PlatformColor.code*` raised to its Increase Contrast variant in light (standard system hues fall under 4.5:1 on the white surface), never a raw system hue. No code themes or theme setting.
- **Monospace is only `Font.code(_:)`** (Commit Mono), in rows `.codeListRow` / `.codeDetailRow`, never `.monospaced()` or `monospacedSystemFont`. It's for what the machine says (paths, keys, values, counts, timings, status); prose and controls stay in the system face.

## Motion

- **Motion is for continuity and feedback, never ambient.** No loops except `PosterSkeleton` (while `RemoteImage` loads) and iOS's `ListeningPulse` (while Activity is connected), both still under Reduce Motion. No motion on the response body.
- **System springs, not hand-tuned curves:** `.snappy` for movement, `.smooth` for large layout, `.bouncy` only for a landing the user caused, never chrome. Every motion has a Reduce Motion variant (`accessibilityReduceMotion`): movement becomes a crossfade or nothing.
- **Leaving is faster than arriving.** Resting, empty, and error states use `restingStateTransition()` (`rising:` only where the state doesn't hold the request bar, which must not move), and sections settle in upward, never sideways. An animation attached to a transition runs even in a plain unanimated transaction, so never attach one to rows that `switchWorkspace` or `reset` replace.
- Motion design starts with `find-animation-opportunities`, and motion code gets `review-animations` before committing (not for a `numericText` value change or a system component's own transition); `improve-animations` only when asked. These skills are written for the web: where they disagree with this section (system springs, the allowed loops), this section wins.

## Working here

- Every change follows the `change-workflow` skill (branch, verify, pre-merge checklist, pull request, review, merge on approval); a release follows `release-workflow`. Issues and pull requests live on GitHub (`matthewlyle/dev-tools`): `github-issue` files them, `work-issue` hands them to worker agents on mini. All four are in `.agents/skills/`. A feature is done only when that checklist passes, in the same commit.
- Xcode project uses synchronized groups: add or move files on disk and they're in the target. No `pbxproj` edits.
- `xcodebuild` is the verifier: macOS and the iOS Simulator both build and the tests (Swift Testing, `DevToolsTests/`) pass before a commit; the commands are in `change-workflow`. SourceKit diagnostics in this workspace report the whole module as unresolved ("Cannot find type … in scope"); they are noise.
- NEVER take screenshots (`screencapture`) or script/drive the running app on the owner's Mac — it grabs their whole screen, and a second instance clashes with their Xcode session. Agents on mini use their own simulator through `xcrun simctl` instead (`change-workflow`, "Look at it"). Otherwise reason from the code, and leave visual confirmation to the owner, telling them precisely what to check.
- Tests are fixture-driven and target contracts (parsers, URL building, spec matching, redaction, cURL). Add one when you add a contract; don't test plumbing.
- Persistence goes through `AppSupportStore`, `Codable`, tolerant of old files (unknown keys ignored, new keys optional).
- A `Local` connection on an iOS device triggers the local-network privacy prompt (`INFOPLIST_KEY_NSLocalNetworkUsageDescription`); the simulator never asks, so networking changes need a device check against a LAN server.
- The Mac app ships as a notarized DMG on the `site/` landing page, deployed to Vercel with the CLI (`release-workflow`), never Git integration: the DMG is gitignored, so a Git deploy ships the page without it. `site/privacy.html` states what the app sends and stores; a change to either (a new host, a new stored file, anything identifying) updates it in the same commit.
- iOS ships through TestFlight (`Tools/upload-ios.sh`). iOS keeps its own version (`MARKETING_VERSION[sdk=iphoneos*]` and `[sdk=iphonesimulator*]`) apart from the Mac's: TestFlight reviews the first build of every version, so iOS stays on its reviewed version between uploads and moves only when it's submitted to the App Store. App Store Connect rejects an iOS icon with an alpha channel, so iOS has its own flattened `icon_ios_1024.png` (`Icon/build-icon.sh` writes it). `PrivacyInfo.xcprivacy` declares the app's required-reason API use (UserDefaults, CA92.1) and no collected data; a new required-reason API (file timestamps, disk space, system uptime, …) needs an entry there or the upload is rejected.
- One commit per coherent change; the message explains why and records the constraint behind any non-obvious choice.
