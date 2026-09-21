# dev-tools — Plex API Playground

Native macOS developer tool for exploring the Plex Media Server API. Postman-shaped, but it *knows* Plex: handles auth, discovers servers, navigates the resource tree, and renders responses as hyperlinked, browsable documents.

## Decisions

| Topic | Decision |
|---|---|
| Platform | macOS 26+ (Liquid Glass). Xcode 27.1, Swift 6, strict concurrency. |
| UI | SwiftUI + `@Observable`. `NavigationSplitView` three-pane. Liquid Glass via `glassEffect` / `GlassEffectContainer` on floating chrome (status bar, param chips, activity badges). |
| Deps | Minimal. None planned for v1; reassess only if the hand-rolled XML/JSON highlighter proves inadequate. |
| Bundle ID | `mldgg.devtools` |
| Methods | **GET only** in v1. No PUT/DELETE/POST. |
| Standalone | No shared code with other projects. |
| Persistence | Tokens → Keychain. Everything else → JSON files in `~/Library/Application Support/dev-tools/`. |

## v1 scope

1. Sign in (PIN flow) + server picker with connection probing — done
2. Request builder + response inspector (Raw / Headers), history — done
3. Resource tree browser: Pretty / Tree tabs, hyperlinked responses, back/forward
4. Spec integration: endpoint catalog by tag, parameter autocomplete, pagination controls, response-customization panel
5. Media Query builder
6. Live WebSocket activity monitor
7. Saved requests

Deferred to v1.1: code export (cURL/Swift/Python/JS), non-GET methods, JWT auth, API-version diff mode.

## The spec

developer.plex.tv is a Redoc site; the full OpenAPI 3.1 document (207 paths, 260 operations, 64 schemas, 24 tags, plus long-form docs on media queries, pagination, response customization, auth) is embedded in the page as `__redoc_state`. `Tools/extract-spec.sh` pulls and minifies it into `DevTools/Resources/plex-openapi.json`. It replaces the hand-written cookbook and quick links and drives autocomplete.

## Architecture

```
UI (SwiftUI)  →  Stores (@Observable, @MainActor)  →  ServerSession
                                                        ├─ PlexHTTP        raw request/response
                                                        ├─ NotificationSocket
                                                        └─ ResponseDocument (XML/JSON → Node tree)
              Persistence: Keychain (tokens) + JSON files (saved, history, server cache)
```

**Principle: raw bytes are the source of truth.** No typed models for server responses. Every view is a projection of `Data` + content-type → `Node` tree. Unknown endpoints render fine.

### Folder layout (single app target)

```
dev-tools/
  DevTools.xcodeproj
  DevTools/
    DevToolsApp.swift            @main, WindowGroup(main) + Settings
    Core/
      Identity/
        ClientIdentity.swift     X-Plex-Client-Identifier (UUID persisted), Product, Version, Platform, Device headers
      Auth/
        PINAuthenticator.swift   POST /api/v2/pins?strong=true, poll GET /api/v2/pins/{id}
        TokenStore.swift         Keychain wrapper (Security.framework), account token
        PlexTVClient.swift       plex.tv: PIN, /api/v2/user, /api/v2/resources
      Discovery/
        PlexResource.swift       decoded /api/v2/resources entry + connections
        ConnectionProber.swift   race /identity across connections; rank local>remote>relay
        ConnectedServer.swift    machineID, name, baseURL, accessToken, connection kind
      HTTP/
        PlexRequest.swift        method(GET), path, query [QueryParam], headers, accept (.xml/.json). Token is always the X-Plex-Token header, never the query
        PlexResponse.swift       status, headers, body Data, contentType, duration, byteCount
        PlexHTTP.swift           URLSession wrapper; builds URLRequest from PlexRequest + ConnectedServer + ClientIdentity
      Parse/
        Node.swift               name, attributes [String:String], children [Node], text
        XMLNodeParser.swift      XMLParserDelegate → Node
        JSONNodeParser.swift     JSONSerialization → Node (MediaContainer/Metadata isomorphism)
        ResponseDocument.swift   Data + contentType → Node? + pretty-printed raw string
        Highlighter.swift        XML/JSON tokenizer → AttributedString
        LinkDetector.swift       attribute names that are navigable paths (key, parentKey, grandparentKey, thumb, art, theme, librarySectionKey, Location/path ...)
      Socket/
        NotificationSocket.swift URLSessionWebSocketTask → /:/websockets/notifications (plural; Plex's OpenAPI doc misspells it singular); reconnect w/ backoff
        NotificationEvent.swift  type, timestamp, raw payload, parsed Node
      Persistence/
        AppSupportStore.swift    JSON file read/write in Application Support
        SavedRequest.swift       id, name, notes, PlexRequest, serverMachineID?
        HistoryEntry.swift       PlexRequest + status + duration + timestamp
        ServerCache.swift        last resources list for instant sidebar on launch
    Stores/
      AccountStore.swift         sign-in state, user, sign-out
      ServerStore.swift          resources, probe results, selected server, connection override
      RequestStore.swift         current PlexRequest, send, in-flight, last PlexResponse, back/forward stack
      ActivityStore.swift        socket state, events ring buffer (cap 2000), filters, paused
      LibraryStore.swift         saved requests, history, cookbook (bundled cookbook.json)
    Features/
      SignIn/                    PIN code display, "Open plex.tv/link", polling state
      Sidebar/                   Servers section, Saved, Cookbook, History, Activity
      Request/                   path field, query param table (add/remove/enable), header table, accept toggle, token placement, URL preview, Send
      Response/                  StatusBar (status, time, size, content-type), tabs: Pretty / Raw / Tree / Headers
        PrettyView/              MediaContainer summary → item cards/table; inline thumbnails; every link attribute is a Button
        RawView/                 highlighted text, wrap toggle, find, copy
      Browser/                   breadcrumb bar, back/forward, "well-known children" quick links per node type
      Activity/                  event list, type filter chips, pause/clear, payload inspector split
      Saved/                     save-as sheet, edit name/notes, cookbook detail
    Resources/
      cookbook.json
      Assets.xcassets
  DevToolsTests/
    XMLNodeParserTests, JSONNodeParserTests, HighlighterTests, LinkDetectorTests, ConnectionProberTests (fixture-driven)
```

## Key behaviors

**Auth.** `POST https://plex.tv/api/v2/pins?strong=true` with X-Plex headers → `{id, code}`. Open `https://app.plex.tv/auth#?clientID=…&code=…&context[device][product]=…` in browser. Poll `GET /api/v2/pins/{id}` until `authToken` non-null. Store in Keychain. Fetch `/api/v2/user` for display.

**Discovery.** `GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1` with `Accept: application/json`. Filter `provides` contains `server`. Per resource, probe connections concurrently on `GET {uri}/identity` with the resource's `accessToken`; accept first whose `machineIdentifier` matches. Rank: local https → local http → remote https non-relay → remote → relay. Show each connection with latency; user can pin one.

**Requests.** GET only; method picker hidden in v1. Path + query params editable. Token is always sent as the `X-Plex-Token` header, never in the URL, and is never displayed or copyable. Response format is an app-wide setting (`Accept: application/json` by default, or `application/xml`, which is what PMS sends without an Accept header). Container paging params (`X-Plex-Container-Start/Size`) offered as header toggles. Every send appends to history.

**Hyperlinks.** `LinkDetector` marks attributes whose values are server paths (`key`, `parentKey`, `grandparentKey`, `thumb`, `art`, `theme`, `composite`, `librarySectionKey`, `hubKey`, …). In Pretty and Tree views these are buttons: click → `RequestStore` loads the path, pushes current onto back stack, sends. Resolution follows the documented rule: every request path is treated as having a trailing slash, so `/library/sections + home → /library/sections/home`; absolute paths are used as-is; `https://` and `view://` keys pass through (opened externally / not navigable). Image attributes render inline via `/photo/:/transcode?url=…&width=…&height=…` (server-relative) or directly (absolute URLs).

**Endpoint catalog (M4).** Spec operations grouped by tag in the content column. Click → path template loads into the builder; `{sectionId}`-style placeholders prompt for values (sections from the current server where applicable). Typed parameters with descriptions feed the Parameters editor as an autocomplete list. Documented headers (`X-Plex-Container-Start/Size/Focus-Key`, `X-Plex-Pms-Api-Version`, `X-Plex-Client-Profile-*`) offered in the Headers editor.

**Pagination (M4).** Read `X-Plex-Container-Start` / `X-Plex-Container-Total-Size` response headers and `offset`/`size`/`totalSize` on `MediaContainer`; status bar shows "40–59 of 1,204" with prev/next that adjust the container headers, plus a size=0 "count only" shortcut.

**Response customization (M4).** Panel for `includeFields` / `excludeFields` / `includeElements` / `excludeElements` / `includeOptionalFields` / `includeOptionalElements`, populated from attribute and element names seen in the last response.

**Media Query builder (M5).** Visual builder emitting the documented querystring language: per-type operators (`=`, `!=`, `==`, `!==`, `<=`, `>=`, `>>=`, `<<=`), relative dates with unit suffixes (`>>=-3y`), field scoping (`show.title`), `sort=field:desc,other`, `group=`, `limit=`, and `push=1`/`pop=1`/`or=1` for parentheses. Fields come from `/library/sections/{id}?includeDetails=1` (`Field` elements).

**Activity (M6).** Connect `wss://{host}/:/websockets/notifications?X-Plex-Token=…` (ws for http servers; note the plural — Plex's own OpenAPI doc lists the singular `/:/websocket/…`, which 404s). Events arrive as `{NotificationContainer: {type, size, <TypeArray>: [...]}}`. Types to filter: `playing`, `timeline`, `activity`, `progress`, `status`, `backgroundProcessingQueue`, `transcodeSession.update/end`, `reachability`, `preference`. Ring buffer capped at 2000; pause freezes list without dropping socket.

## Liquid Glass usage

- Only where the system puts it: sidebar and toolbar via `NavigationSplitView`, the segmented section switcher and search field as toolbar items, and the Send button (`.glassProminent`).
- No custom `glassEffect` anywhere. The HIG reserves glass for the controls/navigation layer floating above content; the response status readout, pagination, badges, and cards are content, so they use standard fills (`.fill.tertiary`, `.quaternary`).
- Content areas (raw text, cards) stay opaque for readability.
## Milestones

Each ends with a smoke-test proof, not a test suite.

1. **Skeleton + auth + discovery.** Done.
2. **Request/response core.** Done.
3. **Parse + Pretty + Tree + hyperlinks + browser.** `Node` parsers, Tree outline, Pretty cards w/ thumbnails, link detection, back/forward, breadcrumbs. *Proof: from `/library/sections` click down to one item's metadata and back without typing.*
4. **Spec integration.** Endpoint catalog by tag (replaces `QuickLinks`), parameter/header autocomplete, pagination controls, response-customization panel. *Proof: pick `/library/sections/{sectionId}/all` from the catalog, fill the section, page through results with prev/next.*
5. **Media Query builder.** *Proof: build "movies added in the last 3 years, unwatched, sorted by rating desc" visually; emitted query returns the expected items.*
6. **Activity monitor.** Socket, event list, filters, payload inspector. *Proof: start playback on any client; `playing` and `timeline` events appear live; pause/resume works.*
7. **Saved requests.** Save-as, edit, delete. *Proof: quit/relaunch; saved requests persist.*
8. **Polish.** Shortcuts, error/empty states, app icon, glass tuning.

## Tests (targeted, fixture-driven)

- `XMLNodeParser` / `JSONNodeParser`: same fixture in both formats → identical `Node` tree.
- `Highlighter`: token boundaries on tricky inputs (attributes with `=` in values, escaped quotes, nested arrays).
- `LinkDetector`: relative-vs-absolute `key` resolution; non-path values (`ratingKey` numeric) not linked as paths.
- `ConnectionProber.rank`: ordering invariants.
- Socket payload decoding for each notification type from captured fixtures.

## Open items

- Refresh cadence for the bundled spec (manual via script for now).
- Whether the Pretty view should decode `type` integers to names using the spec's metadata type table.
