import Foundation
import Testing
@testable import DevTools

@MainActor
struct RequestWorkspaceTests {
    private func store() -> RequestStore {
        let identity = ClientIdentity(
            clientIdentifier: "test", product: "Tests", version: "0", platform: "macOS",
            platformVersion: "0", device: "Mac", deviceName: "Mac"
        )
        return RequestStore(http: PlexHTTP(identity: identity), memory: ValueMemory())
    }

    @Test func eachSectionKeepsItsOwnRequest() {
        let requests = store()
        requests.load(PlexRequest(path: "/library/sections"))
        requests.switchWorkspace(from: "Endpoints", to: "History")
        #expect(requests.current.path == "/")

        requests.load(PlexRequest(path: "/butler"))
        requests.switchWorkspace(from: "History", to: "Endpoints")
        #expect(requests.current.path == "/library/sections")

        requests.switchWorkspace(from: "Endpoints", to: "History")
        #expect(requests.current.path == "/butler")
    }

    @Test func restoredRequestsTakeTheCurrentResponseFormat() {
        let requests = store()
        let format = requests.acceptFormat
        requests.load(PlexRequest(path: "/butler"))
        requests.switchWorkspace(from: "Endpoints", to: "History")
        let other = AcceptFormat.allCases.first { $0 != format }!
        requests.acceptFormat = other
        requests.switchWorkspace(from: "History", to: "Endpoints")
        #expect(requests.current.accept == other)
        requests.acceptFormat = format
    }

    @Test func aServerSwitchDiscardsEverySection() {
        let requests = store()
        requests.load(PlexRequest(path: "/library/sections"))
        requests.switchWorkspace(from: "Endpoints", to: "History")
        requests.resetAllWorkspaces()
        requests.switchWorkspace(from: "History", to: "Endpoints")
        #expect(requests.current.path == "/")
    }
}
