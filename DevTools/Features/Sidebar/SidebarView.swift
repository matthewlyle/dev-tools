import SwiftUI

struct SidebarView: View {
    @Binding var selection: String?

    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    var body: some View {
        List(selection: $selection) {
            Section("Servers") {
                ForEach(servers.sortedEntries) { entry in
                    ServerRow(
                        entry: entry,
                        active: servers.activeProbe(for: entry),
                        avatarURL: entry.resource.owned ? account.user?.thumbURL : servers.ownerAvatar(for: entry.resource)
                    )
                        .tag(entry.id)
                }
                if servers.entries.isEmpty {
                    Text(servers.isRefreshing ? "Loading…" : (servers.errorMessage ?? "No servers"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    guard let token = account.token else { return }
                    Task { await servers.refresh(token: token) }
                } label: {
                    Label("Refresh Servers", systemImage: "arrow.clockwise")
                }
                .disabled(servers.isRefreshing)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AccountFooter()
        }
    }
}

private struct ServerRow: View {
    let entry: ServerStore.Entry
    let active: ProbeResult?
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            .background(.quaternary, in: .circle)
            .clipShape(.circle)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.resource.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // The subtitle already says it in words; the dot is redundant colour.
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if entry.isProbing, entry.probes.isEmpty { return "Probing…" }
        if let active, case .ok(let latency) = active.outcome {
            return "\(active.connection.kind.rawValue) · \(latency.milliseconds) ms"
        }
        if !entry.probes.isEmpty { return "Unreachable" }
        return entry.resource.productVersion ?? "Not probed"
    }

    private var statusColor: Color {
        if active != nil { return .green }
        if entry.isProbing { return .orange }
        if !entry.probes.isEmpty { return .red }
        return .gray
    }
}

private struct AccountFooter: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers
    @State private var confirmingSignOut = false

    var body: some View {
        if let user = account.user {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    AsyncImage(url: user.thumbURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(.circle)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(user.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    // Signing out forces a fresh PIN flow, so it asks first.
                    Menu {
                        Button("Sign Out…", role: .destructive) { confirmingSignOut = true }
                    } label: {
                        Label("Account", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .confirmationDialog("Sign out of \(user.title)?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) {
                            account.signOut()
                            servers.clear()
                        }
                    } message: {
                        Text("You'll need to approve a new sign-in on plex.tv to use the app again.")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }
}

extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
