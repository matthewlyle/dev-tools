# Agent rules for dev-tools

Native macOS 26 SwiftUI app: a Plex Media Server API playground. Read `PLAN.md` for scope and architecture. These are the rules that aren't obvious from the code.

## Comments: almost never

Default to none. Code says *what*; a comment is only for a *why* the code can't carry. The bar: would a competent reader, six months from now, otherwise change this and break something?

Keep only:
- An external constraint — a Plex quirk, a HIG rule, a SwiftUI/AppKit limitation, a performance cliff — and what it forces here.
- A deliberate policy that looks like an omission (`// Credentials are shown masked and can't be copied out, by design.`).
- A non-obvious invariant or ordering dependency.

Never:
- Restate the code, name the type, or narrate steps (`// Set the title`, `// { [`).
- `// MARK:` — the files are short; organise with types instead.
- Doc comments on things whose signature already says it all.
- TODOs. Do it or drop it.
- Anecdotes. State the constraint, never the encounter: no "this showed up as", "we would have missed", "the X case", counts, timings, or specific values met along the way. A rule must stand without its origin story; the story belongs in the commit message.

A `///` on a type or function is fine when it meets the bar above; most don't. When you touch a file, delete comments that fail the bar. Commit messages carry the narrative, not the source.

## Load-bearing decisions

- **Tokens are never shown and never in a URL.** `X-Plex-Token` travels only as a header; `PlexRequest.url(base:)` cannot emit it; cURL export uses `$PLEX_TOKEN`; masked values have no copy path. Do not add a reveal, toggle, or query-string option.
- **The server is the navigation context.** Sidebar = servers only. Endpoints / History / Activity are views onto the selected server, never peers of it. Saved requests are a pinned group *inside* the endpoint list, not a section or a scope.
- **Every toolbar item has a menu bar command** (`AppCommands.swift`). Un-undoable destructive actions confirm.
- **Code face is Commit Mono** through `Typeface` / `Font.code(_:)`. Never `.monospaced()` or `NSFont.monospacedSystemFont` directly.
- **Large bodies:** wrap is forced above 256 KB and JSON is pretty-printed above the highlight limit. Unwrapped text in `NSTextView` lays out the whole document on the main thread. Don't relax either.
- **WebSocket path is `/:/websockets/notifications` (plural).** Plex's own OpenAPI doc lists it singular, which the server 404s. There is no EventSource transport; don't add one.
- **`Resources/plex-openapi.json` is generated** by `Tools/extract-spec.sh`. Never hand-edit it; fix consumers instead.
- **Response format (`Accept`) is an app-wide setting**, not per request. History replays use the current setting.

## Design: the HIG, as applied here

We follow Apple's Human Interface Guidelines for macOS. Below is how that resolved in this app; when in doubt, read the HIG page, not another app.

**Chrome must earn its place.** Every visible control or label in a header costs attention. Before adding one: is it already shown elsewhere in the window (the title bar names the server — don't repeat it)? Could it be a tooltip, a popover, a menu item, or a Settings default instead? The request bar is `GET [path] ⓘ [Send]`; keep it that way.

**Layout**
- Three-column `NavigationSplitView`. Toolbar shape is fixed: title leading, one segmented section switcher in the centre (`.secondaryAction`), each section's filter/search in the trailing slot. Never two segmented controls in the toolbar; SwiftUI has no column-aligned toolbar sections on macOS, so don't try to put items "over" a column.
- Column layout is narrow: lists use two-line rows, not tables. Use `Table` only where there's width (response headers). Sorting in a narrow list goes in a toolbar menu.
- Sheets for short targeted input (save, placeholders); popovers for reference (endpoint docs); never a popover for a warning. No auxiliary windows.

**Toolbar placement** — decide this when adding the control, not at review.
- The toolbar is for things that act on *what the column shows*: switching the view, filtering or searching it, sorting it, clearing it. If a control acts on the *object being edited* — the request's path, params, headers, send, save, copy — it lives beside that object in the request bar. If it acts on a sub-pane (Raw view's wrap, fold, copy body), it lives in that pane's own header row.
- Values and preferences are never toolbar items: a pop-up in the body, or Settings if app-wide.
- Status and information never go in the toolbar. Title and `navigationSubtitle` are the only text there.
- Each section owns the trailing slot and declares its own items from its view; when the section changes, its items go with it. Aim for at most three trailing items before the search field.
- Toolbar items are icon-only `Label`s, no bezels, standard SF Symbols. Every one must also exist as a menu bar command — the toolbar is never a command's only home, because users can hide or customise it.
- The Probe/Connect/Refresh class of rare actions belongs in the menu bar only; the toolbar is for what you do repeatedly.

**Menu bar** — Apple's rules, as they land in `AppCommands.swift`.
- The menu bar lists *every* command the app has. Toolbar buttons, context-menu items, and keyboard shortcuts are conveniences on top of a menu item, never substitutes for one.
- Put a command in the menu people expect: **App** (About, Settings… ⌘,), **File** (documents: save/open/close), **Edit** (text and clipboard), **View** (what's shown and how — section switcher, Wrap Lines), **Window**, **Help**. App-specific commands go in custom menus between View and Window: **Server** (act on the selected server: Refresh, Probe/Connect, Clear History…) and **Request** (act on the request in the bar: Save, Copy as cURL, Send, Cancel, Focus Path, Back, Forward). Don't invent a third menu when one of these fits.
- Order within a menu: most frequent first; group related items with separators; keep menus short; submenus sparingly and one level deep.
- Labels are verb phrases in Title Case with no articles. Trailing `…` when the command needs more input before acting. A command that toggles uses a checkmark (inline `Picker`/`Toggle`) or a changeable label (Show/Hide); never both.
- Unavailable commands are *dimmed*, never removed — the menu's shape stays stable. Gate on state (`activeServer == nil`, `!requests.isSending`); for commands that act on the visible section, publish a `FocusedValues` action from that view and disable when it's absent.
- Shortcuts: `⌘` primary; `⇧⌘` for the sibling of a `⌘` command; `⌥` rarely; `⌃` never. Only frequent commands get one. Never repurpose a standard shortcut (`⌘Z X C V A F S W N Q ,` and the system's `⌘Space`, `⌘Tab`, `⌘←→`). Taken here: `⌘1/2/3` sections · `⌘R` Refresh Servers · `⌘S` Save Request… · `⇧⌘C` Copy as cURL · `⌘↩` Send · `⌘.` Cancel · `⌘L` Focus Path · `⌘[` `⌘]` Back/Forward · `⌘,` Settings · `⌘F` find in body (system). Add new ones to this list.
- Menu item icons: none, unless a whole group gets them.

**Liquid Glass**
- Never apply `glassEffect` yourself. Glass is the system's controls/navigation layer — toolbar, sidebar, `.glassProminent` on Send. Everything in a content pane (status readouts, pagination, badges, cards, the sign-in card) uses standard fills: `.fill.tertiary`, `.quaternary`, `.regularMaterial`.

**Controls**
- Segmented control = switching views. A *value* is a pop-up (`Picker` `.menu`), or a Settings default if it's app-wide.
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
- The OpenAPI spec is a guide, not truth. `required` is frequently absent, so a documented-but-unsent parameter shows as a hint on a 400, not a block on sending. Documented params feed autocomplete; users can still type anything.


## Feature definition of done

A feature is complete when every line below is true, in the same commit. This is what makes app-wide reviews unnecessary.

1. **Placement decided** by the toolbar rule above: column → toolbar; object → request bar; sub-pane → its header. Nothing repeats what the title bar shows.
2. **Menu bar command** in the right menu, dimmed (not hidden) when unavailable, shortcut only if frequent and not taken.
3. **Controls chosen by kind**: segmented for views, pop-up for values, Settings for app-wide preferences, checkbox for a single body option, `role: .destructive` on destructive actions, confirmation only if un-undoable.
4. **Accessible**: icon-only controls are `Label` + `.iconOnly`; decorative symbols hidden; colour never the only signal; a `.help` tooltip on every icon-only control.
5. **States covered**: empty (`ContentUnavailableView` with a next step), loading (unlabelled spinner, nothing blocked), error (inline, says what to do), and disabled when there's no server.
6. **Copy**: Title Case controls, sentence-case descriptions, verbs on buttons, `…` on commands that ask first.
7. **Token policy** holds: nothing new shows, copies, or URL-encodes a credential.
8. **Persistence** through `AppSupportStore`, `Codable`, tolerant of old files (unknown keys ignored, new keys optional).
9. **Tests** for any new contract — parsing, URL/string building, matching, redaction — none for plumbing.
10. **Verified on screen** by launching the built app, not by reading the code back.
11. **Docs**: `PLAN.md` scope updated; a new load-bearing decision goes in this file.
12. **One commit**, message explains why.
## Working here

- Xcode project uses synchronized groups: add or move files on disk and they're in the target. No `pbxproj` edits.
- Build: `xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'platform=macOS' -derivedDataPath DerivedData/Build build`. Test: same with `test` (Swift Testing, `DevToolsTests/`). Both must be green before a commit.
- Tests are fixture-driven and target contracts (parsers, URL building, spec matching, redaction, cURL). Add one when you add a contract; don't test plumbing.
- Verify UI changes on screen (`screencapture`), not by reading the code back.
- One commit per coherent change; the message explains why and records the constraint behind any non-obvious choice.
- SourceKit diagnostics in this workspace report the whole module as unresolved ("Cannot find type … in scope"). They are noise; `xcodebuild` is the verifier.
