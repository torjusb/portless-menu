import AppKit
import PortlessCore
import SwiftUI

struct PortsideApp: App {
    @State private var store = StateStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            if case .proxyDown = store.snapshot {
                Image(systemName: "network.slash")
            } else {
                Image(systemName: "network")
                Text("\(store.snapshot.urls.count)")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    let store: StateStore

    var body: some View {
        switch store.snapshot {
        case .proxyDown:
            Text("Portless proxy is not running")
            Divider()
            Text("Start an app with: portless run <command>")
        case .noRoutes(let proxy):
            Text("No active routes")
            Divider()
            Text(statusLine(proxy))
        case .routes(let proxy, let groups):
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.urls) { URLItem(active: $0) }
                }
            }
            Divider()
            Text(statusLine(proxy))
            Text("Hold Option to copy a URL")
        }
        Divider()
        Button("Refresh") { store.refresh() }
            .keyboardShortcut("r")
        Button("Quit Portside") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func statusLine(_ proxy: ProxyState) -> String {
        "Proxy running on port \(proxy.port) (\(proxy.tls ? "HTTPS" : "HTTP"))"
    }
}

struct URLItem: View {
    let active: ActiveURL

    var body: some View {
        Button("\(active.hostname)  →  :\(String(active.targetPort))") {
            NSWorkspace.shared.open(active.url)
        }
        .modifierKeyAlternate(.option) {
            Button("Copy \(active.url.absoluteString)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(active.url.absoluteString, forType: .string)
            }
        }
    }
}
