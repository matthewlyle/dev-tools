# dev-tools — Plex API Playground

Native macOS developer tool for exploring the Plex Media Server API. Postman-shaped, but it *knows* Plex: handles auth, discovers servers, drives every documented endpoint from the spec, and renders responses as highlighted, browsable documents.

## Decisions

| Topic | Decision |
|---|---|
| Platform | macOS 26+ (Liquid Glass). Xcode 27.1, Swift 6, strict concurrency. |
| UI | SwiftUI + `@Observable`. `NavigationSplitView` three-pane. Liquid Glass only where the system puts it (toolbar, sidebar, `.glassProminent` Send); no custom `glassEffect`. System accent and semantic colours; no custom accent. |
| Deps | Minimal. None planned for v1; reassess only if the hand-rolled XML/JSON highlighter proves inadequate. |
| Bundle ID | `mldgg.devtools` |
| Methods | **GET only** in v1. No PUT/DELETE/POST. |
| Standalone | No shared code with other projects. |
| Persistence | Tokens → Keychain. Everything else → JSON files in `~/Library/Application Support/dev-tools/`. |

## v1 scope

1. Sign in (PIN flow) + server picker with connection probing — done
2. Request builder + response inspector (Raw / Headers), history — done
3. Response browser: back/forward between requests, breadcrumbs — done. The structured Pretty view and in-response hyperlinks were removed; a redesigned Pretty view is deferred.
4. Spec integration: endpoint catalog by tag, parameter autocomplete, pagination controls, response-customization panel — done
5. Media Query builder — deferred (not started)
6. Live WebSocket activity monitor — done (connect/disconnect, clear, type filters; no pause)
7. Saved requests — done

Deferred to v1.1: code export (cURL/Swift/Python/JS), non-GET methods, JWT auth, API-version diff mode.

## The spec

developer.plex.tv is a Redoc site; the full OpenAPI 3.1 document (207 paths, 260 operations, 64 schemas, 24 tags, plus long-form docs on media queries, pagination, response customization, auth) is embedded in the page as `__redoc_state`. `Tools/extract-spec.sh` pulls and minifies it into `DevTools/Resources/plex-openapi.json`. It replaces the hand-written cookbook and quick links and drives autocomplete.

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
        Folding.swift            fold regions from tokens (Raw view collapse)
        ResponseDocument.swift   Data + contentType → text, tokens, folds, format, Node tree (size-gated)
        ResponseShape.swift      attribute/element names in the last response → includeFields/excludeElements vocabulary
      Spec/
        OpenAPISpec.swift        Codable model of the bundled OpenAPI document
        SpecCatalog.swift        operations grouped by tag, placeholder matching, access scopes, documented headers
      Socket/
        NotificationTransport.swift  URLSessionWebSocketTask → /:/websockets/notifications (plural); reconnect with backoff
        NotificationEvent.swift  type, timestamp, raw payload
      Persistence/
        AppSupportStore.swift    JSON read/write in ~/Library/Application Support/dev-tools/
        SavedRequest.swift       id, name, notes, PlexRequest, server
        HistoryEntry.swift       PlexRequest + status + duration + error + date
    Stores/
      AccountStore.swift         sign-in state, user, sign-out
      ServerStore.swift          resources + probe results, selected server, persisted servers snapshot
      RequestStore.swift         current request, send/replay, in-flight, last response + document, history, back/forward, section cache
      SavedStore.swift           saved requests per server
      SpecStore.swift            loads the bundled spec into a SpecCatalog
      ValueMemory.swift          id-like values seen per server for placeholder suggestions; last-used per placeholder
      ActivityStore.swift        socket status, events ring buffer (cap 2000), type filters, selection
    Features/
      SignIn/                    PIN code, "Open plex.tv/link", polling state
      Sidebar/                   MainSplitView (three columns, section switcher, preload + reset on switch), SidebarView (servers)
      Servers/                   ServerDetailView — server header + the selected section's list
      Endpoints/                 EndpointListView (catalog by tag, Saved pinned first, lock on admin-only when shared), PlaceholderSheet
      Request/                   WorkspaceView (request bar → nav → response; editable vs read-only), RequestBarView, KeyValueEditor
      Browser/                   NavigationBar — back/forward + breadcrumbs (shown once there's a response)
      Response/                  ResponseView (status bar, Raw/Headers tabs, 400/403 hints), RawResponseView + CodeTextView (highlight, wrap, fold), HeadersView
      History/                   HistoryListView — read-only replay; selecting auto-runs without recording
      Activity/                  ActivityControlsView (connect/disconnect, clear, event types), ActivityEventsView (events + payload inspector)
      Saved/                     SavedRequestRow
      Settings/                  SettingsView — app-wide response format
    Resources/
      plex-openapi.json          generated by Tools/extract-spec.sh
      Fonts/                     Commit Mono
    Assets.xcassets              AppIcon, Hosts (Simple Icons host marks)
  DevToolsTests/
    NodeParserTests, HighlighterTests, FoldingTests, JSONFormatterTests, ResponseShapeTests,
    SpecCatalogTests, ValueMemoryTests, CurlExporterTests, PlexRequestURLTests, ConnectionRankingTests
```

## Key behaviors

**Auth.** `POST https://plex.tv/api/v2/pins?strong=true` with X-Plex headers → `{id, code}`. Open `https://app.plex.tv/auth#?clientID=…&code=…&context[device][product]=…` in browser. Poll `GET /api/v2/pins/{id}` until `authToken` non-null. Store in Keychain. Fetch `/api/v2/user` for display.

**Discovery.** `GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1` with `Accept: application/json`. Filter `provides` contains `server`. Per resource, probe connections concurrently on `GET {uri}/identity` with the resource's `accessToken`; accept first whose `machineIdentifier` matches. Rank: local https → local http → remote https non-relay → remote → relay. Show each connection with latency; user can pin one.

**Requests.** GET only; method picker hidden in v1. Path + query params editable. Token is always sent as the `X-Plex-Token` header, never in the URL, and is never displayed or copyable. Response format is an app-wide setting (`Accept: application/json` by default, or `application/xml`, which is what PMS sends without an Accept header). Container paging params (`X-Plex-Container-Start/Size`) offered as header toggles. Every send from the builder appends to history; replaying an entry from History does not.

**Response browsing.** Back/forward between sent requests, with a breadcrumb of the current path. In-response hyperlinks and the structured Pretty/Tree views were removed; responses render as highlighted Raw text and a Headers table. A redesigned Pretty view is deferred; when it returns it will re-introduce navigable link attributes and inline thumbnails via `/photo/:/transcode`.

**Endpoint catalog (M4).** Spec operations grouped by tag in the content column. Click → path template loads into the builder; `{sectionId}`-style placeholders prompt for values (sections from the current server where applicable). Typed parameters with descriptions feed the Parameters editor as an autocomplete list. Documented headers (`X-Plex-Container-Start/Size/Focus-Key`, `X-Plex-Pms-Api-Version`, `X-Plex-Client-Profile-*`) offered in the Headers editor.

**Pagination (M4).** Read `X-Plex-Container-Start` / `X-Plex-Container-Total-Size` response headers and `offset`/`size`/`totalSize` on `MediaContainer`; status bar shows "40–59 of 1,204" with prev/next that adjust the container headers, plus a size=0 "count only" shortcut.

**Response customization (M4).** Panel for `includeFields` / `excludeFields` / `includeElements` / `excludeElements` / `includeOptionalFields` / `includeOptionalElements`, populated from attribute and element names seen in the last response.

**Media Query builder (M5).** Visual builder emitting the documented querystring language: per-type operators (`=`, `!=`, `==`, `!==`, `<=`, `>=`, `>>=`, `<<=`), relative dates with unit suffixes (`>>=-3y`), field scoping (`show.title`), `sort=field:desc,other`, `group=`, `limit=`, and `push=1`/`pop=1`/`or=1` for parentheses. Fields come from `/library/sections/{id}?includeDetails=1` (`Field` elements).

**Activity (M6).** Connect `wss://{host}/:/websockets/notifications?X-Plex-Token=…` (ws for http servers; note the plural — Plex's own OpenAPI doc lists the singular `/:/websocket/…`, which 404s). Events arrive as `{NotificationContainer: {type, size, <TypeArray>: [...]}}`. Types to filter: `playing`, `timeline`, `activity`, `progress`, `status`, `backgroundProcessingQueue`, `transcodeSession.update/end`, `reachability`, `preference`. Ring buffer capped at 2000. No pause: connect/disconnect and clear only.

## Liquid Glass usage

- Only where the system puts it: sidebar and toolbar via `NavigationSplitView`, the segmented section switcher and search field as toolbar items, and the Send button (`.glassProminent`).
- No custom `glassEffect` anywhere. The HIG reserves glass for the controls/navigation layer floating above content; the response status readout, pagination, badges, and cards are content, so they use standard fills (`.fill.tertiary`, `.quaternary`).
- Content areas (raw text, cards) stay opaque for readability.

## Milestones

Each ends with a smoke-test proof, not a test suite.

1. **Skeleton + auth + discovery.** Done.
2. **Request/response core.** Done — Raw / Headers inspector, history with read-only replay.
3. **Parse + browser.** `Node` parsers, back/forward, breadcrumbs — done. The structured Pretty view and in-response hyperlinks were removed; a redesigned Pretty view is deferred.
4. **Spec integration.** Endpoint catalog by tag, parameter/header autocomplete, pagination controls, response-customization panel — done.
5. **Media Query builder.** Not started (deferred).
6. **Activity monitor.** Socket, event list, type filters, payload inspector — done. No pause; connect/disconnect + clear. *Proof: start playback on any client; `playing`/`timeline` events appear live.*
7. **Saved requests.** Save-as, edit, delete — done.
8. **Polish.** Shortcuts, error/empty states, app icon, glass tuning, read-only history replay — in progress.

## Tests (targeted, fixture-driven)

- `NodeParserTests`: the same fixture as XML and JSON → identical `Node` tree; element names/order kept; booleans match XML integers; ids unique.
- `HighlighterTests`: token boundaries on tricky inputs (attributes with `=` in values, escaped quotes, nested arrays).
- `FoldingTests` / `JSONFormatterTests`: fold regions and key-order/number-preserving pretty printing.
- `ResponseShapeTests`: field/element vocabulary derived from a container's items.
- `SpecCatalogTests`: spec loading, tag grouping/filtering, placeholder matching and filling, docs links, access from security scopes.
- `ValueMemoryTests`: placeholder suggestions matched by stem, per-server isolation.
- `CurlExporterTests` / `PlexRequestURLTests`: cURL uses `$PLEX_TOKEN`; the URL never contains the token.
- `ConnectionRankingTests`: connection ranking invariants.

## Open items

- Refresh cadence for the bundled spec (manual via script for now).
- Redesign the Pretty view (removed): structured, media-aware rendering of a `MediaContainer`, plus whether to decode `type` integers to names using the spec's metadata type table.
