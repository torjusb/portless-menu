import Foundation
import PortlessCore

@main
enum Entry {
    @MainActor
    static func main() {
        guard CommandLine.arguments.contains("--list") else {
            PortsideApp.main()
            return
        }
        let snapshot = StateReader.current()
        if case .proxyDown = snapshot {
            FileHandle.standardError.write(Data("portless proxy is not running\n".utf8))
        }
        for active in snapshot.urls {
            print(active.url.absoluteString)
        }
    }
}
