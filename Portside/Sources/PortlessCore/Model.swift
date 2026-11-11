import Foundation

public struct Route: Decodable, Equatable, Sendable {
    public let hostname: String
    public let port: Int
    public let pid: pid_t

    public init(hostname: String, port: Int, pid: pid_t) {
        self.hostname = hostname
        self.port = port
        self.pid = pid
    }
}

public struct ProxyState: Equatable, Sendable {
    public let port: Int
    public let tls: Bool

    public init(port: Int, tls: Bool) {
        self.port = port
        self.tls = tls
    }

    public func url(for hostname: String) -> URL? {
        let scheme = tls ? "https" : "http"
        let defaultPort = tls ? 443 : 80
        let authority = port == defaultPort ? hostname : "\(hostname):\(port)"
        return URL(string: "\(scheme)://\(authority)")
    }
}

public struct ActiveURL: Equatable, Sendable, Identifiable {
    public let url: URL
    public let hostname: String
    public let targetPort: Int
    public let pid: pid_t
    public let project: String

    public var id: String { hostname }

    public init?(route: Route, proxy: ProxyState) {
        guard let url = proxy.url(for: route.hostname) else { return nil }
        self.url = url
        hostname = route.hostname
        targetPort = route.port
        pid = route.pid
        let labels = route.hostname.split(separator: ".")
        project = labels.count >= 2 ? String(labels[labels.count - 2]) : route.hostname
    }
}

public struct ProjectGroup: Equatable, Sendable, Identifiable {
    public let name: String
    public let urls: [ActiveURL]

    public var id: String { name }

    static func grouping(_ urls: [ActiveURL]) -> [ProjectGroup] {
        Dictionary(grouping: urls, by: \.project)
            .map { ProjectGroup(name: $0.key, urls: $0.value.sorted { $0.hostname < $1.hostname }) }
            .sorted { $0.name < $1.name }
    }
}

public enum Snapshot: Equatable, Sendable {
    case proxyDown
    case noRoutes(ProxyState)
    case routes(ProxyState, [ProjectGroup])

    init(proxy: ProxyState?, routes: [Route]) {
        guard let proxy else {
            self = .proxyDown
            return
        }
        let urls = routes.compactMap { ActiveURL(route: $0, proxy: proxy) }
        self = urls.isEmpty ? .noRoutes(proxy) : .routes(proxy, ProjectGroup.grouping(urls))
    }

    public var urls: [ActiveURL] {
        guard case .routes(_, let groups) = self else { return [] }
        return groups.flatMap(\.urls)
    }
}
