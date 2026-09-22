# iPhone — what an iOS version needs

The app is one universal target that already builds and runs on iPadOS (`TARGETED_DEVICE_FAMILY = 2`). "An iOS version" means letting that target run on iPhone. Nothing about the model, stores, networking, parsing or persistence is Mac- or iPad-specific any more; every remaining problem is **width**. iPhone is a compact horizontal size class (portrait ≈ 390–430 pt), and the current layout assumes a regular one.

This is also the same work that makes the iPad correct in Split View and Slide Over, which are compact too and are currently wrong for the same reasons.

## Where it stands

Works as-is on a compact width:
- Sign-in card, connecting splash, Settings sheet, Save/Placeholder sheets.
- The Media query builder (`Form`), the request/response header block, `CodeTextView` (the hosted header, folding, find, wrap), `HeadersView`, the poster grid, the lightbox, the Activity events list with its payload `.inspector` (a sheet in compact, like Media), the server title menu, the More menu, keyboard shortcuts on hardware keyboards.
- Persistence (`AppSupportStore` uses the sandboxed Application Support directory), Keychain, the client identity (already reports `iOS`/`iPad`; `device` would want `iPhone`).

Does not work on a compact width:
- `MainSplitView` (iPad branch) lays the section list and the detail side by side in an `HStack` — the list at 40 % clamped to 320–460 pt, which is the whole phone.
- The header row (status pill · pagination · tabs · fold/wrap/copy) and `KeyValueEditor` rows (toggle · name · value · values menu · remove) are single lines sized for ≥ 600 pt.
- The `ServerInfoView` and endpoint-docs `.popover`s become full sheets on iPhone unless told otherwise.
- History has no delete path without a keyboard: `onDeleteCommand` is Mac-only and the context menu is long-press.

## Required

### 1. Build settings (`project.pbxproj`, app target)
- `TARGETED_DEVICE_FAMILY = "1,2"`.
- `INFOPLIST_KEY_UISupportedInterfaceOrientations` for iPhone (portrait; landscape optional — the response body benefits from it, the rest doesn't need it).
- `INFOPLIST_KEY_NSLocalNetworkUsageDescription`. On a device, connecting to a LAN address (`Local` connections, `192.168.…plex.direct`) triggers the local-network privacy prompt and fails silently without this string. The simulator doesn't enforce it, which is why the iPad build appears to work; this is a latent bug for iPad devices too.
- ATS: `plex.direct` is HTTPS. If plain-`http` connections are ever used (`Connection.kind` allows it), `NSAllowsLocalNetworking` is required. Decide whether to allow or to filter those connections out on iOS.
- App icon already has the universal 1024 entry; launch screen is generated.

### 2. Navigation model on compact width (the decision)
The single-header, two-pane layout has no compact equivalent. Two HIG-conformant shapes; one has to be chosen.

**A. Tab bar.** Endpoints · History · Activity · Media as tabs, each tab a `NavigationStack` whose root is that section's list and whose pushed screen is its detail (request/response, event payload, poster grid). The server is the title menu in every tab's navigation bar, and Refresh Servers / Connect sit in it as they do now on Mac and iPad; Settings… stays in a trailing More menu.
- For: the HIG's iPhone idiom for switching between top-level areas; iOS 26 tab bars minimise on scroll and can host a search tab; the segmented control's "no more than about five segments on iPhone" limit is moot.
- Against: AGENTS.md currently classes the four sections as *views onto one server*, not app sections, and picked a segmented control for exactly that reason; on iPhone this becomes a documented exception. Four tabs plus an implicit "server" scope is fine; adding a fifth tab for servers would be the wrong move (the title menu stays).

**B. Segmented control in the navigation bar** with a single `NavigationStack`: list at the root, detail pushed.
- For: identical model to Mac/iPad, no exception to record.
- Against: four segments in a 390 pt bar next to a title is cramped; `.principal` replaces the title on iOS (the server name disappears — the same thing that bit the iPad build); `.toolbarRole(.editor)` doesn't apply in compact. Realistically the control would have to sit in the list's content, which is the layout the iPad rejected.

Recommendation: **A**, selected by `horizontalSizeClass == .compact` so the iPad keeps its current layout in full-screen and gets tabs in Split View. Implemented as a third branch of `MainSplitView` alongside the macOS and iPad ones — the section list and detail pane views themselves don't change.

### 3. Section list → detail as a push
In compact width the list can't sit beside the detail. Each section's list pushes its detail:
- Endpoints: tapping an endpoint (or a saved request) pushes the workspace with the request loaded. Today selection loads the request into the bar in place; on compact it also navigates.
- History: tapping an entry pushes the read-only workspace (already replays on selection).
- Activity: `ActivityEventsView` already uses `.inspector`, which presents as a sheet in compact — the same as Media, so no compact branch is needed.
- Media: the builder's Run Query pushes the results; the poster inspector already adapts (`.inspector` presents as a sheet in compact).
A `NavigationPath`/selection binding per section, held where the section state already lives (`RequestStore.current`, `ActivityStore.selectedEventID`, `MediaQueryStore`), so pushes survive tab switches.

### 4. Rows and header for 390 pt
- **Header block, row 2**: status pill and tabs stay; pagination controls and the body controls (fold all / expand all / Wrap / copy) move out. Two defensible homes: a trailing More menu in the navigation bar, or a bottom toolbar (HIG: iPhone bottom bar for actions on the current view). Bottom toolbar is the better fit — the controls act on the body you're reading.
- **`KeyValueEditor` rows**: two lines per parameter (name over value) or a `List` with swipe-to-delete replacing the remove button; the enabled switch stays leading. The documented-values menu can hang off the value field.
- **Request bar**: `GET [path] ⓘ [Send]` fits; the URL preview line already truncates in the middle. Back/forward can stay at its head.
- **`ServerInfoView`**: fine as a sheet, or keep it a popover with `.presentationCompactAdaptation(.popover)`. Same for `OperationDocs`.
- **`HeadersView` grid**: two columns wrap; acceptable. Long values may want `.lineLimit` with expansion.
- **`ResponseStatusBar`**: drop the content type on compact if the row still overflows.

### 5. Touch equivalents for keyboard/pointer paths
- History delete: `.swipeActions` (and `onDelete`) on the rows; the context menu stays.
- Saved request rename/delete: swipe actions alongside the existing context menu.
- Every `.help(…)` is a tooltip, pointer-only; anything whose meaning depended on it needs its label visible or an accessibility label (most already have `Label` titles).
- The lightbox closes on backdrop tap and on `.cancelAction` (Esc, or a hardware keyboard's back), the same path on both platforms.

### 6. Lifecycle
- Backgrounding severs the WebSocket. `ActivityStore` reconnects with backoff, but not on return from background: observe `scenePhase` and reconnect when active if the user had connected.
- Sign-in opens plex.tv in Safari and polls; on iPhone the app is backgrounded during approval, so polling must resume on return (`scenePhase` again, or it simply continues if the task is still alive — verify).

## Should

- **Dynamic Type** for code: `CodeTextView` uses a fixed 12 pt `Typeface.code`. On iPhone, scale from `.footnote`/`.body` so the body respects the user's text size.
- **`ClientIdentity`**: `device: "iPhone"` when `UIDevice.current.userInterfaceIdiom == .phone`, so the server lists it correctly.
- **Landscape**: allow it on iPhone for the response body; the tab bar handles the rest.
- **Search**: with a tab bar, iOS 26 can make search a tab; otherwise `.searchable` on each list root as now.

## Not needed

- No new stores, parsers, network code, or persistence. Nothing in `Core/` changes except `ClientIdentity` and possibly a device-idiom check.
- No separate target. Same bundle, same universal build.
- No Liquid Glass work: tab bars and toolbars are the system's; the content stays on standard fills.

## Verification

- iPhone simulator (iOS 27) in portrait and landscape, and an iPad simulator in Split View at 1/3 width — both must render the compact layout.
- On a **device**: connect to a `Local` server (this is where `NSLocalNetworkUsageDescription` is exercised; the simulator won't show the problem).
- Every section: list → detail push and back; History delete by swipe; Activity connect → event → payload; Media run → posters → inspector sheet.
- Unit tests are unaffected (they target contracts, none of this touches them); run the macOS suite to prove nothing regressed.

## Order of work

1. Build settings, local-network string, device family. Confirm the app launches on an iPhone simulator (it will render badly; that's expected).
2. Compact branch of `MainSplitView` with the chosen navigation model; section lists pushing their details.
3. `ActivityEventsView` compact branch.
4. Header row and `KeyValueEditor` compact layouts; bottom toolbar for body controls.
5. Swipe actions; `scenePhase` reconnects.
6. Record the compact-width decision in `AGENTS.md` (navigation model, the tab-bar exception if A) and update `PLAN.md` scope.

Rough size: the navigation model (2–3) is most of it; the rest is a day of layout.
