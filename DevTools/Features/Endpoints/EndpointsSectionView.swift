import SwiftUI

/// Which endpoints the section shows: everything the spec documents, or
/// the ones you've kept for this server.
enum EndpointScope: String, CaseIterable, Identifiable {
    case all = "All"
    case saved = "Saved"

    var id: String { rawValue }
}

/// The Endpoints section: the spec catalog or the saved list, with the
/// scope switch in the toolbar slot this section owns.
struct EndpointsSectionView: View {
    let entry: ServerStore.Entry
    let server: ConnectedServer?

    @AppStorage("endpointScope") private var scope: EndpointScope = .all

    var body: some View {
        Group {
            switch scope {
            case .all:
                EndpointListView(server: server)
            case .saved:
                SavedListView(serverID: entry.id)
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $scope) {
                    ForEach(EndpointScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("All documented endpoints, or the ones saved for this server")
            }
        }
    }
}
