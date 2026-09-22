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

- **Tokens are never shown and never in a URL.** `X-Plex-Token` travels only as a header; `PlexRequest.url(base:)` cannot emit it; cURL export uses `$PLEX_TOKEN`; masked values have no copy path. Artwork goes through `ImageStore` → `PlexHTTP` for the same reason — never `AsyncImage` with a token in the query string. Do not add a reveal, toggle, or query-string option.
- **The server is the scope, chosen from the title.** The window title is the selected server and its title menu (`toolbarTitleMenu` → `ServerMenu`) switches it and opens Server Info… — the HIG's document menu beside the title — with the same list in the **Server** menu bar menu. On iPad the rare actions (Refresh Servers, Connect, Settings…) sit in a trailing More menu; nothing else earns a header button. There is no servers sidebar: a sidebar is for navigating areas of an app, and a server isn't an area, it's what every area is a view of. Endpoints / History / Activity / Media are views onto the selected server, never peers of it. Saved requests are a pinned group *inside* the endpoint list, not a section or a scope. The account (avatar, Sign Out…) lives in Settings, plus the App menu on macOS.
- **Every toolbar item has a menu bar command** (`AppCommands.swift`). Un-undoable destructive actions confirm.
- **Code face is Commit Mono** through `Typeface` / `Font.code(_:)`. Never `.monospaced()` or `NSFont.monospacedSystemFont` directly.
- **Large bodies:** wrap is forced above 256 KB and JSON is pretty-printed above the highlight limit. Unwrapped text in `NSTextView` lays out the whole document on the main thread. Don't relax either. The body text view is always the scroller — never inside a page `ScrollView` (that forces full layout). The request/response block scrolls *with* it because `CodeTextView` hosts it inside the text view's own scroll (top content inset = header height; header hosted via `NSHostingController`/`UIHostingController`, environment handed over with `.environment(\.self, context.environment)`).
- **WebSocket path is `/:/websockets/notifications` (plural).** Plex's own OpenAPI doc lists it singular, which the server 404s. There is no EventSource transport; don't add one.
- **`Resources/plex-openapi.json` is generated** by `Tools/extract-spec.sh`. Never hand-edit it; fix consumers instead.
- **Response format (`Accept`) is an app-wide setting**, not per request. History replays use the current setting.
- **One universal target, macOS + iPadOS (iPad-only family).** Views are shared SwiftUI; every platform difference goes through `Core/Platform.swift`, never a raw `NS*`/`UI*` type in a feature file. Images/fonts/colours are `PlatformImage`/`PlatformFont`/`PlatformColor`; clipboard is `Clipboard.copy`, opening a URL is `SystemBrowser.open`, and the macOS-only modifiers have `platform…` wrappers (`platformNavigationSubtitle`, `platformCheckboxToggleStyle`, `.platformToolbar` search). `#if os(macOS)` in a feature view is for genuine layout differences, not API shims (`HSplitView`, `onExitCommand`/`onDeleteCommand`, the section switcher); reach for a helper in `Platform.swift` first. macOS keeps the `Settings` scene; iPadOS presents `SettingsView` as a sheet from Settings… in the trailing More menu (⌘,) — the HIG keeps settings buttons out of toolbars. Sandbox/hardened-runtime/entitlements are scoped `[sdk=macosx*]`. `CodeTextView` is an `NSTextView` on macOS and a `UITextView` on iPadOS behind one type, sharing the attributed-string renderer.
- **One header over the whole window on both platforms**: title (server + menu) leading, the segmented section switcher centre via `.secondaryAction`, the section's filter/search trailing. macOS gets this from a two-column `NavigationSplitView` (section list | detail). iPad has no toolbar spanning split columns, so `MainSplitView` lays the list and detail out as two panes under one `NavigationStack` bar with `.toolbarRole(.editor)` — the role that keeps the title leading while `.secondaryAction` fills the centre. Never `.principal` on iOS: it replaces the title.

## Design: the HIG, as applied here

We follow Apple's Human Interface Guidelines for macOS. Below is how that resolved in this app; when in doubt, read the HIG page, not another app.

**Chrome must earn its place.** Every visible control or label in a header costs attention. Before adding one: is it already shown elsewhere in the window (the title bar names the server — don't repeat it)? Could it be a tooltip, a popover, a menu item, or a Settings default instead? The request bar is `GET [path] ⓘ [Send]`; keep it that way.

**Layout**
- Two columns: the selected section's list, then its detail. Toolbar shape is fixed: title (server, with its menu) leading, one segmented section switcher in the centre (`.secondaryAction`), each section's filter/search in the trailing slot. Never two segmented controls in the toolbar; SwiftUI has no column-aligned toolbar sections on macOS, so don't try to put items "over" a column.
- Column layout is narrow: lists use two-line rows, not tables; response headers are a `Grid` inside the tab's scroll so the request block can scroll with them. Sorting in a narrow list goes in a toolbar menu.
- Sheets for short targeted input (save, placeholders); popovers for reference (endpoint docs); never a popover for a warning. No auxiliary windows.

**Toolbar placement** — decide this when adding the control, not at review.
- The toolbar is for things that act on *what the column shows*: switching the view, filtering or searching it, sorting it, clearing it. If a control acts on the *object being edited* — the request's path, params, headers, send, save, copy — it lives beside that object in the request bar. If it acts on a sub-pane (the Response pane's wrap, fold, copy body), it lives in that pane's own header row.
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
- Shortcuts: `⌘` primary; `⇧⌘` for the sibling of a `⌘` command; `⌥` rarely; `⌃` never. Only frequent commands get one. Never repurpose a standard shortcut (`⌘Z X C V A F S W N Q ,` and the system's `⌘Space`, `⌘Tab`, `⌘←→`). Taken here: `⌘1/2/3/4` sections · `⌘R` Refresh Servers · `⌘S` Save Request… · `⇧⌘C` Copy as cURL · `⌘↩` Send (runs the built query in Media) · `⌘⌫` Delete History Item · `⌘I` Show/Hide Info (Media poster) · `⌘.` Cancel · `⌘L` Focus Path · `⌘[` `⌘]` Back/Forward · `⌘,` Settings · `⌘F` find in body (system). Add new ones to this list.
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

**Animation** — motion is for continuity, never decoration.
- Animate only when something *changes in place* and the user needs to track it: a number updating, a row appearing or leaving, a disclosure opening, a state flipping. Static layouts stay static; nothing animates on appear, and nothing loops.
- SwiftUI idioms: scope every animation to the value that changed with `.animation(_, value:)`, never a bare `withAnimation` around unrelated state. Numbers roll with `.contentTransition(.numericText(value:))`; swapped text crossfades with `.interpolate`. Use the system springs (`.snappy` default, `.smooth` for large layout, `.bouncy` only for something playful) rather than hand-tuned curves or durations; leave system components (lists, disclosures, sheets, menus) to their own motion.
- Reduced motion is a first-class variant, not an afterthought: read `@Environment(\.accessibilityReduceMotion)` and collapse movement to a crossfade or an instant change. Colour and opacity may still transition.
- Skills — run the animations.dev skills by phase, not as a sweep:
  - Designing a feature that has any motion in it → `find-animation-opportunities` first (read-only; it also says what should stay still), then `motion-brief` if the motion is more than a value change.
  - Implementing → `animate` for easing, duration, and spring choices; `animation-accessibility` for the reduced-motion variant.
  - Before committing motion code → `review-animations`. If it's a value update behind a `numericText` or a system component's own transition, skip the review; the bar is met.
  - `improve-animations` (whole-codebase audit) only when the user asks for one — the point of this section is to not need it.
  - Naming a motion you can picture but not name → `animation-vocabulary`.

## Feature definition of done

A feature is complete when every line below is true, in the same commit. This is what makes app-wide reviews unnecessary.

1. **Placement decided** by the toolbar rule above: column → toolbar; object → request bar; sub-pane → its header. Nothing repeats what the title bar shows.
2. **Menu bar command** in the right menu, dimmed (not hidden) when unavailable, shortcut only if frequent and not taken.
3. **Controls chosen by kind**: segmented for views, pop-up for values, Settings for app-wide preferences, checkbox for a single body option, `role: .destructive` on destructive actions, confirmation only if un-undoable.
4. **Accessible**: icon-only controls are `Label` + `.iconOnly`; decorative symbols hidden; colour never the only signal; a `.help` tooltip on every icon-only control.
5. **States covered**: empty (`ContentUnavailableView` with a next step), loading (unlabelled spinner, nothing blocked), error (inline, says what to do), and disabled when there's no server.
6. **Copy**: Title Case controls, sentence-case descriptions, verbs on buttons, `…` on commands that ask first.
7. **Motion**: anything that changes in place animates per the Animation rule, scoped to its value, with a reduced-motion variant; anything else stays still. Non-trivial motion has been through `animate` and `review-animations`.
8. **Token policy** holds: nothing new shows, copies, or URL-encodes a credential.
9. **Persistence** through `AppSupportStore`, `Codable`, tolerant of old files (unknown keys ignored, new keys optional).
10. **Tests** for any new contract — parsing, URL/string building, matching, redaction — none for plumbing.
11. **Verified on screen** by launching the built app, not by reading the code back.
12. **Docs**: `PLAN.md` scope updated; a new load-bearing decision goes in this file.
13. **One commit**, message explains why.

## Working here

- Xcode project uses synchronized groups: add or move files on disk and they're in the target. No `pbxproj` edits.
- Build: `xcodebuild -project DevTools.xcodeproj -scheme DevTools -destination 'platform=macOS' -derivedDataPath DerivedData/Build build`. Test: same with `test` (Swift Testing, `DevToolsTests/`). Both must be green before a commit.
- Tests are fixture-driven and target contracts (parsers, URL building, spec matching, redaction, cURL). Add one when you add a contract; don't test plumbing.
- Verify UI changes on screen (`screencapture`), not by reading the code back.
- One commit per coherent change; the message explains why and records the constraint behind any non-obvious choice.
- SourceKit diagnostics in this workspace report the whole module as unresolved ("Cannot find type … in scope"). They are noise; `xcodebuild` is the verifier.
