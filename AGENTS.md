# Agent rules for dev-tools

Native macOS 26 SwiftUI app: a Plex Media Server API playground. Read `PLAN.md` for scope and architecture. These are the rules that aren't obvious from the code.

## Comments: almost never

Default to none. Code says *what*; a comment is only for a *why* the code can't carry. The bar: would a competent reader, six months from now, otherwise change this and break something?

Keep only:
- An external constraint — a Plex quirk, a HIG rule, a SwiftUI/AppKit limitation, a measured performance cliff — and what it forces here.
- A deliberate policy that looks like an omission (`// Credentials are shown masked and can't be copied out, by design.`).
- A non-obvious invariant or ordering dependency.

Never:
- Restate the code, name the type, or narrate steps (`// Set the title`, `// { [`).
- `// MARK:` — the files are short; organise with types instead.
- Doc comments on things whose signature already says it all.
- TODOs. Do it or drop it.

A `///` on a type or function is fine when it meets the bar above; most don't. When you touch a file, delete comments that fail the bar. Commit messages carry the narrative, not the source.

## Load-bearing decisions

- **Tokens are never shown and never in a URL.** `X-Plex-Token` travels only as a header; `PlexRequest.url(base:)` cannot emit it; cURL export uses `$PLEX_TOKEN`; masked values have no copy path. Do not add a reveal, toggle, or query-string option.
- **The server is the navigation context.** Sidebar = servers only. Endpoints / History / Activity are views onto the selected server, never peers of it. Saved requests are a pinned group *inside* the endpoint list, not a section or a scope.
- **Every toolbar item has a menu bar command** (`AppCommands.swift`). Un-undoable destructive actions confirm.
- **Code face is Commit Mono** through `Typeface` / `Font.code(_:)`. Never `.monospaced()` or `NSFont.monospacedSystemFont` directly.
- **Large bodies:** wrap is forced above 256 KB and JSON is pretty-printed above the highlight limit. Unwrapped text in `NSTextView` lays out the whole document on the main thread (~2.5 s/MB). Don't relax either.
- **WebSocket path is `/:/websockets/notifications` (plural).** Plex's own OpenAPI doc misspells it singular and it 404s. EventSource was removed; don't reintroduce it.
- **`Resources/plex-openapi.json` is generated** by `Tools/extract-spec.sh`. Never hand-edit it; fix consumers instead.
- **Response format (`Accept`) is an app-wide setting**, not per request. History replays use the current setting.


## Design: the HIG, as applied here

We follow Apple's Human Interface Guidelines for macOS. Below is how that resolved in this app; when in doubt, read the HIG page, not another app.

**Chrome must earn its place.** Every visible control or label in a header costs attention. Before adding one: is it already shown elsewhere in the window (the title bar names the server — don't repeat it)? Could it be a tooltip, a popover, a menu item, or a Settings default instead? The request bar is `GET [path] ⓘ [Send]`; keep it that way.

**Layout**
- Three-column `NavigationSplitView`. Toolbar shape is fixed: title leading, one segmented section switcher in the centre (`.secondaryAction`), each section's filter/search in the trailing slot. Never two segmented controls in the toolbar; SwiftUI has no column-aligned toolbar sections on macOS, so don't try to put items "over" a column.
- Column layout is narrow: lists use two-line rows, not tables. Use `Table` only where there's width (response headers). Sorting in a narrow list goes in a toolbar menu, as Mail does.
- Sheets for short targeted input (save, placeholders); popovers for reference (endpoint docs); never a popover for a warning. No auxiliary windows.

**Liquid Glass**
- Never apply `glassEffect` yourself. Glass is the system's controls/navigation layer — toolbar, sidebar, `.glassProminent` on Send. Everything in a content pane (status readouts, pagination, badges, cards, the sign-in card) uses standard fills: `.fill.tertiary`, `.quaternary`, `.regularMaterial`.

**Controls**
- Segmented control = switching views. A *value* is a pop-up (`Picker` `.menu`), or a Settings default if it's app-wide — that's why `Accept` left the request bar.
- One prominent button per view (Send). Destructive actions use `role: .destructive`; only un-undoable ones confirm (Clear History, Sign Out, Delete saved) — Disconnect and Clear Events don't.
- Checkbox for a single minor option in the body (Wrap); switch only for an emphasised or grouped setting. Toggles never in a toolbar.
- Icon-only buttons are `Label("Verb", systemImage:)` + `.labelStyle(.iconOnly)`, never a bare `Image`, so VoiceOver gets the verb. Decorative symbols get `.accessibilityHidden(true)`. Status colours are always paired with words; the dot is redundant.
- Spinners are unlabelled; the sentence above them says what's happening. Never "Loading…". Don't block the panel while sending — the spinner replaces Send's icon and the last response stays readable.
- Empty states are `ContentUnavailableView` with a next step in the description.
- Numbers that change in place roll with `.contentTransition(.numericText(value:))`.

**Colour, type, icons**
- System semantic colours only. Anything hashed to a colour maps into the 12-colour system palette, never raw HSL.
- Text styles for hierarchy; no Light/Thin weights; no hand-set `.tracking`. Monospace only via `Font.code(_:)`.
- SF Symbols used for their meaning. There are no OS/brand logos in SF Symbols: host marks come from bundled Simple Icons (`Assets/Hosts`, template vectors) plus `apple.logo`; Windows is hand-drawn. App icon is Lucide `braces` on the 1024 grid.

**Copy**
- Title Case for controls, menu items, headers, empty-state titles; sentence case for descriptions and status lines. Verbs on buttons. Trailing `…` when a control needs more input first (`Save Request…`, `Clear History…`). Errors say what to do, next to the thing that failed.

**Spec**
- The OpenAPI spec is a guide, not truth. `required` is frequently absent (ultrablur's params), so a documented-but-unsent parameter shows as a hint on a 400, not a block on sending. Documented params feed autocomplete; users can still type anything.
## Working here

- Xcode project uses synchronized groups: add or move files on disk and they're in the target. No `pbxproj` edits.
- Build: `xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'platform=macOS' -derivedDataPath DerivedData/Build build`. Test: same with `test` (Swift Testing, `DevToolsTests/`). Both must be green before a commit.
- Tests are fixture-driven and target contracts (parsers, URL building, spec matching, redaction, cURL). Add one when you add a contract; don't test plumbing.
- Verify UI changes on screen (`screencapture`), not by reading the code back.
- One commit per coherent change; the message explains why, and records any gotcha you hit so the next reader doesn't rediscover it.
- SourceKit diagnostics in this workspace report the whole module as unresolved ("Cannot find type … in scope"). They are noise; `xcodebuild` is the verifier.
