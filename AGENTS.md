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
- **Toolbar shape is fixed:** title leading, one segmented section switcher in the centre (`.secondaryAction`), each section's filter/search trailing. Never a second segmented control in the toolbar.
- **No custom Liquid Glass.** Glass is the system's controls/navigation layer only. Anything in the content pane — status readouts, pagination, badges, cards — uses standard fills. `.glassProminent` on Send is the one system exception.
- **Every toolbar item has a menu bar command** (`AppCommands.swift`). Un-undoable destructive actions confirm.
- **Code face is Commit Mono** through `Typeface` / `Font.code(_:)`. Never `.monospaced()` or `NSFont.monospacedSystemFont` directly.
- **Large bodies:** wrap is forced above 256 KB and JSON is pretty-printed above the highlight limit. Unwrapped text in `NSTextView` lays out the whole document on the main thread (~2.5 s/MB). Don't relax either.
- **WebSocket path is `/:/websockets/notifications` (plural).** Plex's own OpenAPI doc misspells it singular and it 404s. EventSource was removed; don't reintroduce it.
- **`Resources/plex-openapi.json` is generated** by `Tools/extract-spec.sh`. Never hand-edit it; fix consumers instead.
- **Response format (`Accept`) is an app-wide setting**, not per request. History replays use the current setting.

## Working here

- Xcode project uses synchronized groups: add or move files on disk and they're in the target. No `pbxproj` edits.
- Build: `xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'platform=macOS' -derivedDataPath DerivedData/Build build`. Test: same with `test` (Swift Testing, `DevToolsTests/`). Both must be green before a commit.
- Tests are fixture-driven and target contracts (parsers, URL building, spec matching, redaction, cURL). Add one when you add a contract; don't test plumbing.
- Verify UI changes on screen (`screencapture`), not by reading the code back.
- One commit per coherent change; the message explains why, and records any gotcha you hit so the next reader doesn't rediscover it.
- SourceKit diagnostics in this workspace report the whole module as unresolved ("Cannot find type … in scope"). They are noise; `xcodebuild` is the verifier.
