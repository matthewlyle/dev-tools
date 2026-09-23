# dev-tools — Plex API Playground

Native macOS, iPadOS, and iOS developer tool for exploring the Plex Media Server API. Postman-shaped, but it *knows* Plex: handles auth, discovers servers, drives every documented endpoint from the spec, and renders responses as highlighted, browsable documents.

## Decisions

| Topic | Decision |
|---|---|
| Platform | macOS 26+, iPadOS 26.1+, and iOS 26.1+ (Liquid Glass; 26.1 for the per-tab `tabViewBottomAccessory(isEnabled:)`), one universal app target (iPhone and iPad device families). Xcode 27.1, Swift 6, strict concurrency. |
| UI | SwiftUI + `@Observable`. Two columns (section list, detail) under one header; the server is the window title and its title menu switches it. On a compact width (iPhone, narrow iPad split) each section is a tab: its list at the root, its detail pushed. Liquid Glass only where the system puts it (toolbar, `.glassProminent` Send); no custom `glassEffect`. System accent and semantic colours; no custom accent. |
| Deps | Minimal. None planned for v1; reassess only if the hand-rolled XML/JSON highlighter proves inadequate. |
| Bundle ID | `mldgg.devtools` |
| Methods | **GET only** in v1. No PUT/DELETE/POST. |
| Standalone | No shared code with other projects. |
| Persistence | Tokens → Keychain. Everything else → JSON files in `~/Library/Application Support/dev-tools/`. |

## v1 scope

1. Sign in (PIN flow) + server picker with connection probing — done
2. Request builder + response inspector (Response / Headers), history — done
3. Response browser: back/forward between requests — done (breadcrumbs removed; they repeated the URL). The structured Pretty view and in-response hyperlinks were removed.
4. Spec integration: endpoint catalog by tag, parameter autocomplete, pagination controls — done. The response-customization (include/exclude) menus were removed; `includeFields` etc. are typed as ordinary params
5. Media Query builder — done as the fourth section, "Media" (⌘4): filters with nested `push`/`pop` grouping (AND/OR per group), a tag-value picker over the server's filter values, sort, group, limit
6. Live WebSocket activity monitor — done (connect/disconnect, clear, type filters; no pause; rows name the item they're about)
7. Saved requests — done

## The spec

developer.plex.tv is a Redoc site; the full OpenAPI 3.1 document (207 paths, 260 operations, 64 schemas, 24 tags, plus long-form docs on media queries, pagination, response customization, auth) is embedded in the page as `__redoc_state`. `Tools/extract-spec.sh` pulls and minifies it into `DevTools/Resources/plex-openapi.json`. It replaces the hand-written cookbook and quick links and drives autocomplete.

Metadata types are numbers on the wire (`type=1`, `"type": 4` in payloads) and names only in the spec's prose "List of Metadata Types". `MetadataType` restates that table (a test holds it to the bundled spec): decoded values read `episode (4)` for `type`/`metadataType`, and a query `type` parameter offers the types as documented values. Raw response text is never rewritten.

## Architecture

```
UI (SwiftUI)  →  Stores (@Observable, @MainActor)  →  Core
                                                       ├─ PlexHTTP               raw request/response
                                                       ├─ NotificationTransport  WebSocket notifications
                                                       └─ ResponseDocument       XML/JSON → Node tree + highlighted text
              Persistence: Keychain (account token) + JSON files in Application Support
                           (servers snapshot, saved requests, history, remembered placeholder values)
```

**Principle: raw bytes are the source of truth.** No typed models for server responses. Every view is a projection of `Data` + content-type → `Node` tree. Unknown endpoints render fine.

### Folder layout (single app target)

```
dev-tools/
  DevTools.xcodeproj
  Tools/
    extract-spec.sh              pulls developer.plex.tv's embedded OpenAPI doc → Resources/plex-openapi.json (generated; never hand-edit)
  DevTools/
    DevToolsApp.swift            @main; builds the stores, WindowGroup(main) + Settings scene
    AppCommands.swift            menu bar — every toolbar/context action has a command here
    RootView.swift               sign-in vs main split
    Core/
      Typeface.swift             Commit Mono via Font.code(_:); the only monospace path
      EpochDate.swift            epoch seconds and relative values (`-7d`): which names are dates, readable text, EpochDateButton (calendar, Now, relative choices), EpochReadout
      SheetScaffold.swift        a sheet's frame: Mac panel with bottom buttons, iOS navigation bar with close/confirm roles at the medium detent
      WellBackground.swift       content backdrop: Mac behind-window blur (toggleable), iOS system background with a static accent wash
      Platform.swift             cross-platform shims: PlatformImage/Font/Color, Clipboard, isCompactWidth (never on macOS)
      Identity/
        ClientIdentity.swift     X-Plex-Client-Identifier (persisted UUID) + Product/Version/Platform/Device headers
      Auth/
        PlexTVClient.swift       plex.tv: PIN create/poll, /api/v2/user, /api/v2/resources, friend avatars
        TokenStore.swift         Keychain wrapper for the account token
      Discovery/
        PlexResource.swift       decoded /api/v2/resources entry + Connection (protocol, address, local/relay, rank)
        ConnectionProber.swift   race /identity across connections; rank local https > local http > remote > relay
        ConnectedServer.swift    machineID, name, baseURL, accessToken, chosen connection, owned
      HTTP/
        PlexRequest.swift        GET path, query [QueryParam], headers [HeaderField], accept; url(base:) never emits the token
        PlexResponse.swift       status, headers, body Data, contentType, duration
        PlexHTTP.swift           URLSession wrapper: PlexRequest + ConnectedServer + ClientIdentity → URLRequest; token as X-Plex-Token header
        CurlExporter.swift       request → curl command with $PLEX_TOKEN placeholder
        Pagination.swift         PaginationInfo from X-Plex-Container-* headers / MediaContainer offset,size,totalSize
      Parse/
        Node.swift               name, [Attribute], children; headline
        XMLNodeParser.swift      XMLParser → Node (attributes sorted by name)
        JSONNodeParser.swift     JSONValue → Node (MediaContainer/Metadata isomorphic with XML)
        JSONValue.swift          order-preserving JSON parser
        JSONFormatter.swift      pretty-printer that keeps key order and number formatting
        Highlighter.swift        XML/JSON tokenizer → [Token]
        Folding.swift            fold regions from tokens (Response view collapse)
        ResponseDocument.swift   Data + contentType → text, tokens, folds, format, Node tree (size-gated)
      Query/
        MediaQuery.swift         media query model: typed fields, documented per-type operators, terms/sort/group/limit → PlexRequest; SectionDetails parses Type/Field/Sort
        MediaItem.swift          one container item as read: title, artwork, aspect by type, one-line subtitle, tag vs element child groups; MediaValue decodes units by attribute name
      Spec/
        OpenAPISpec.swift        Codable model of the bundled OpenAPI document
        SpecCatalog.swift        operations grouped by tag, placeholder matching, access scopes, documented headers; labelled value options (schema enums, metadata types for a query `type`)
        MetadataType.swift       the spec's List of Metadata Types (movie 1 … collection 18): section parsing, `movie (1)` labels
      Socket/
        NotificationTransport.swift  URLSessionWebSocketTask → /:/websockets/notifications (plural); reconnect with backoff
        NotificationEvent.swift  type, timestamp, raw payload; ratingKey/state/viewOffset and the row line (payload titles first, else a key); itemTitle(metadata:) names a library item
      Persistence/
        AppSupportStore.swift    JSON read/write in ~/Library/Application Support/dev-tools/
        SavedRequest.swift       id, name, notes, PlexRequest, server
        HistoryEntry.swift       PlexRequest + status + duration + error + date
    Stores/
      AccountStore.swift         sign-in state, user, sign-out
      ServerStore.swift          resources + probe results, selected server, persisted servers snapshot
      RequestStore.swift         current request, send/replay, in-flight, last response + document, history (clear / delete one), back/forward, one workspace per section (parked and restored on a switch, discarded on a server switch), per-server placeholder options cache (sections, playlists, collections, tuner devices)
      MediaQueryStore.swift      the query being built (survives section switches) + per-library details cache from includeDetails=1
      ImageStore.swift           artwork via PlexHTTP (token as header, never in a URL): /photo/:/transcode at pixel size, in-memory cache per server/path/size
      SavedStore.swift           saved requests per server
      SpecStore.swift            loads the bundled spec into a SpecCatalog
      ValueMemory.swift          id-like values seen per server for placeholder suggestions; last-used per placeholder
      ActivityStore.swift        socket status, events ring buffer (cap 2000), type filters, selection, item titles looked up per server + ratingKey
    Features/
      SignIn/                    PIN code, "Open plex.tv/link", polling state; SignOutConfirmation (one dialog for Settings and the App menu)
      Servers/                   MainSplitView (one header: server title menu, section switcher; two columns on macOS, two panes on iPad with a draggable, remembered list width; on a compact width a tab per section, list at the root and detail pushed via showSectionDetail; preload + reset on switch), ServerMenu (title menu: server names + Server Info…, Refresh Servers; Settings… on iPad and iPhone), ServerInfoView (popover from the title: host, version, connection in use)
      Endpoints/                 EndpointListView (catalog by tag, Saved pinned first, lock on admin-only when shared), PlaceholderSheet (enum / server-list pickers, now+date for epochs, Recently Seen)
      Request/                   WorkspaceView (editable RequestBarView vs read-only RequestSummaryBar, handed to ResponseView), KeyValueEditor
      Browser/                   HistoryNavButtons — back/forward at the head of the URL line (Endpoints and History; Media records no navigation, since Back would show a query its form no longer holds)
      Response/                  ResponseView (request bar, then ResponseInfoRow — status · pagination · tabs · body controls, two lines on a compact width — and 400/403 hints — one block that scrolls with the body: hosted inside CodeTextView's scroll, inside the poster grid's ScrollView; and at the top of the Headers tab's ScrollView; the status pill never wraps, it sheds content type → subtype → nothing → measurements as the row narrows, full readout in its tooltip), RawResponseView + CodeTextView (highlight, wrap, fold), BodyControls, HeadersView
      History/                   HistoryListView — read-only replay; selecting auto-runs without recording; delete one (context menu, swipe on a compact width, ⌫, ⌘⌫) or clear; sort/status menu and Clear over the list (toolbar on macOS, beside the filter field on iPad); the detail rests on "Select a request…" (Endpoints' says "Send a request…")
      Activity/                  ActivityFiltersView (the list pane: event-type toggles; ActivityTypeMenu, the same as a toolbar menu on a compact width, where the events are the tab's root), ActivityEventsView (events under ActivityConnectionControl — status, received count, last error, Clear, Connect/Disconnect: the tab bar accessory on a compact width, a floating glass capsule elsewhere — or a Not Connected / Couldn't Connect state when disconnected and empty; payload inspector shown while an event is selected, Hide Info ⌘I deselects)
      MediaQuery/                MediaQueryBuilderView (library/type pickers, filter terms, sorts in precedence order, reordered from a row's context menu or by drag where the form allows, group, limit, live preview, Run / ⌘↩), MediaResultsView (Posters | Response | Headers; poster grid, selection → inspector), MediaInfoView (artwork, title, subtitle, tagline, synopsis, tag sentences, decoded Details, nested elements), RemoteImage
      Saved/                     SavedRequestRow (context menu, or swipe on a compact width: Rename…, Delete…)
      Settings/                  SettingsView — app-wide response format, wrap lines, code theme (System, Xcode, GitHub, Atom One; light and dark), clear all history (confirmed); macOS Settings scene, iOS sheet from the title menu or the App menu (⌘,)
    Resources/
      plex-openapi.json          generated by Tools/extract-spec.sh
      Fonts/                     Commit Mono
    Assets.xcassets              AppIcon, Hosts (Simple Icons host marks)
  DevToolsTests/
    NodeParserTests, HighlighterTests, FoldingTests, JSONFormatterTests,
    SpecCatalogTests, ValueMemoryTests, CurlExporterTests, PlexRequestURLTests, ConnectionRankingTests, MediaQueryTests, PlaceholderOptionTests, MediaItemTests, ContentTypeTests, NotificationEventTests
```

## Key behaviors

**Auth.** `POST https://plex.tv/api/v2/pins?strong=true` with X-Plex headers → `{id, code}`. Open `https://app.plex.tv/auth#?clientID=…&code=…&context[device][product]=…` in browser. Poll `GET /api/v2/pins/{id}` until `authToken` non-null. Store in Keychain. Fetch `/api/v2/user` for display.

**Discovery.** `GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1` with `Accept: application/json`. Filter `provides` contains `server`. Per resource, probe connections concurrently on `GET {uri}/identity` with the resource's `accessToken`; accept first whose `machineIdentifier` matches. Rank: local https → local http → remote https non-relay → remote → relay. Show each connection with latency; user can pin one.

**Requests.** GET only; method picker hidden in v1. Path + query params editable. Token is always sent as the `X-Plex-Token` header, never in the URL, and is never displayed or copyable. Response format is an app-wide setting (`Accept: application/json` by default, or `application/xml`, which is what PMS sends without an Accept header). Container paging params (`X-Plex-Container-Start/Size`) offered as header toggles. Every send from the builder appends to history; replaying an entry from History does not.

**Response browsing.** Back/forward between sent requests, at the head of the URL line. In-response hyperlinks and the structured Pretty/Tree views were removed; responses render as highlighted Raw text and a Headers table.

**Endpoint catalog (M4).** Spec operations grouped by tag in the content column. Click → path template loads into the builder; `{placeholder}`s prompt for values in a sheet, each with the richest helper its value allows: a picker when the spec enumerates it (`element`, `transcodeType`, `identifier`, `index`) or the server can list it (`sectionId` → `/library/sections`, `playlistId` → `/playlists`, `collectionId` → each library's `/collections`, grouped by library, `deviceId` → `/media/grabbers/devices`); a calendar (with Now) and a readable date under the field for epoch placeholders (`…At`, `timestamp`); otherwise a field plus values seen in earlier responses. Listable options are preloaded when a server connects so pickers don't flash. Typed parameters with descriptions feed the Parameters editor as an autocomplete list. Documented headers (`X-Plex-Container-Start/Size/Focus-Key`, `X-Plex-Pms-Api-Version`, `X-Plex-Client-Profile-*`) offered in the Headers editor.

**Pagination (M4).** Read `X-Plex-Container-Start` / `X-Plex-Container-Total-Size` response headers and `offset`/`size`/`totalSize` on `MediaContainer`; status bar shows "40–59 of 1,204" with prev/next that adjust the container headers, plus a size=0 "count only" shortcut.

**Media (M5).** The fourth section. Pick a library and a result type; the types, their `Field`s (with types) and `Sort`s come from `/library/sections/{id}?includeDetails=1`, fetched once per library. Operators are the spec's documented per-type table (integer/boolean/tag/string/date/language) and ride on the query key (`year>>=2000`, URI-encoded); booleans emit `field=1|0`; date values accept relative suffixes (`>>=-3y`), picked from a calendar or a 1 day/week/month/year ago choice, with the value read back under the field (`7 days ago`, `Mar 3, 2024, 10:21 AM`). Filters AND together, or all OR with `or=1` ("Match any"); `sort=field[:desc],…`, `group=`, `limit=`. The emitted query is shown live and runs against `/library/sections/{id}/all`. Results show as a **poster grid** (aspect by type: 2:3, square, 16:9; artwork through `ImageStore`), with the raw Response and Headers a tab away and the pagination controls in the status row. Clicking a poster selects it and opens its metadata in the inspector (View › Show Info, ⌘I): artwork, title, `year · rating · runtime`, tagline, synopsis, tag groups as sentences (Genre: …), then every attribute with units decoded and credentials masked, and nested elements (Media → Part → Stream) collapsed. Not yet expressed: nested `push`/`pop` grouping, `sourceType`/field scoping, and picking tag values from the filter endpoints (tag fields take an id).

**Activity (M6).** Connect `wss://{host}/:/websockets/notifications?X-Plex-Token=…` (ws for http servers; note the plural — Plex's own OpenAPI doc lists the singular `/:/websocket/…`, which 404s). Events arrive as `{NotificationContainer: {type, size, <TypeArray>: [...]}}`. Types to filter: `playing`, `timeline`, `activity`, `progress`, `status`, `backgroundProcessingQueue`, `transcodeSession.update/end`, `reachability`, `preference`. Ring buffer capped at 2000. No pause: connect/disconnect and clear only.
Each row reads `state · subject · progress · position`, e.g. `Paused · The Office — S2 E3 · Diversity Day · 12:34`; a state that only repeats the event type (a `playing` event that is playing) is dropped, since the type badge already says it. The subject is the payload's own words when it has them (`title`/`subtitle`, an Activity's title/subtitle/progress, `message`); a payload naming its item only by key (a playing session, an untitled timeline entry) shows the key until a JSON `GET /library/metadata/<ratingKey>` resolves a title (episode `Show — S2 E3 · Title`, movie `Title (year)`, track `Artist — Title`, else `title`), which crossfades in. Lookups go through `PlexHTTP` (token as header), once per server + ratingKey, failures included, until Clear or a server switch; a failed lookup leaves the key.

## Liquid Glass usage

- Only where the system puts it: the toolbar via `NavigationSplitView`/`NavigationStack`, the segmented section switcher and search field as toolbar items, and the Send button (`.glassProminent`).
- One custom `glassEffect`: Activity's connection capsule on iPad and the Mac, a control floating over the events (on iPhone the same control is the system's tab bar accessory). Otherwise the HIG reserves glass for the controls/navigation layer floating above content; the response status readout, pagination, badges, and cards are content, so they use standard fills (`.fill.tertiary`, `.quaternary`).
- Content areas (raw text, cards) stay opaque for readability.

## Milestones

Each ends with a smoke-test proof, not a test suite.

1. **Skeleton + auth + discovery.** Done.
2. **Request/response core.** Done — Response / Headers inspector, history with read-only replay.
3. **Parse + browser.** `Node` parsers, back/forward, breadcrumbs — done. The structured Pretty view and in-response hyperlinks were removed.
4. **Spec integration.** Endpoint catalog by tag, parameter/header autocomplete, pagination controls — done. Response-customization menus removed.
5. **Media.** Fourth section with library/type pickers, typed filter terms, sort, group, limit, live query preview, `push`/`pop` grouping, tag-value picker — done. *Proof: movies added in the last 3 years, unwatched, sorted by rating desc — `type=1&addedAt>>=-3y&unwatched=1&sort=rating:desc` returns the expected items.*
6. **Activity monitor.** Socket, event list, type filters, payload inspector, item titles in rows — done. No pause; connect/disconnect + clear. *Proof: start playback on any client; `playing`/`timeline` events appear live.*
7. **Saved requests.** Save-as, edit, delete — done.
8. **Polish.** Shortcuts, error/empty states, app icon, glass tuning, read-only history replay, liveliness motion (poster-grid entrance stagger, artwork decode crossfade, live activity-event insertion, section-switch crossfade, response status settle, empty states fading out as content arrives, poster press and selection settle, parameter and header rows in and out with a rolling count, Activity connection status that pulses while connecting and bounces on connect), resizable iPad list pane — done.
9. **iPhone.** Compact-width shell (a tab per section, list → pushed detail, Edit Request on Endpoints), two-line response info row and parameter rows, swipe actions on History and Saved, iPhone client identity, local-network usage string, Activity reconnect on return from the background — done.

## Tests (targeted, fixture-driven)

- `NodeParserTests`: the same fixture as XML and JSON → identical `Node` tree; element names/order kept; booleans match XML integers; ids unique.
- `HighlighterTests`: token boundaries on tricky inputs (attributes with `=` in values, escaped quotes, nested arrays).
- `FoldingTests` / `JSONFormatterTests`: fold regions and key-order/number-preserving pretty printing.
- `SpecCatalogTests`: spec loading, tag grouping/filtering, placeholder matching and filling, docs links, access from security scopes.
- `ValueMemoryTests`: placeholder suggestions matched by stem, per-server isolation.
- `CurlExporterTests` / `PlexRequestURLTests`: cURL uses `$PLEX_TOKEN`; the URL never contains the token.
- `ConnectionRankingTests`: connection ranking invariants.
- `MediaQueryTests`: operator characters ride on the key and URL-encode; booleans emit 1/0; empty terms skipped; `or=1` under Match any; sort/group/limit order; `SectionDetails` parsing of Type/Field/Sort.
- `PlaceholderOptionTests`: playlists/collections map `ratingKey`/`title` (collections carry their library as a group); tuner devices fall back through `key`/`uuid`/`id` and `title`/make+model.
- `MediaItemTests`: aspect by type; movie/episode subtitle composition; thumb fallback through parent art; tag groups vs element groups; unit decoding by attribute name (size, bitrate, epoch `*At`, runtime).
- `NotificationEventTests`: ratingKey (digits only, from `ratingKey`, `itemID` or a metadata key), state and viewOffset from playing/timeline/activity payloads; payload titles skip the lookup; item titles from metadata for episode/movie/track/other.
- `EpochDateTests`: `…At`/`timestamp` names (also behind an operator) are dates and `originallyAvailableAt` isn't; only operator keys take relative values; relative values read in the spec's units; small numbers aren't dates; picked dates round-trip as whole seconds.
- `MetadataTypeTests`: the table matches the bundled spec's List of Metadata Types; `type`/`metadataType` numbers decode to `name (n)`, names and unknown numbers and other `*Type` attributes don't; a query `type` parameter offers every type.
