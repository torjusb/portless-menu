import Foundation

public enum PidStatus: Sendable {
    case running
    case notPermitted
    case gone
}

public typealias PidProbe = @Sendable (pid_t) -> PidStatus

public let systemPidProbe: PidProbe = { pid in
    if kill(pid, 0) == 0 { return .running }
    return errno == EPERM ? .notPermitted : .gone
}

public enum StateReader {
    public static let watchedFiles: Set<String> = ["routes.json", "proxy.port", "proxy.pid", "proxy.tls"]

    public static func resolveStateDir(
        environment: [String: String],
        home: URL,
        legacyDir: URL = URL(fileURLWithPath: "/tmp/portless"),
        probe: PidProbe
    ) -> URL {
        if let dir = environment["PORTLESS_STATE_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        let userDir = home.appendingPathComponent(".portless")
        return [userDir, legacyDir].first { readProxy(stateDir: $0, probe: probe) != nil } ?? userDir
    }

    public static func snapshot(stateDir: URL, probe: PidProbe) -> Snapshot {
        Snapshot(proxy: readProxy(stateDir: stateDir, probe: probe), routes: readRoutes(stateDir: stateDir, probe: probe))
    }

    public static func current(probe: PidProbe = systemPidProbe) -> Snapshot {
        let dir = resolveStateDir(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser,
            probe: probe
        )
        return snapshot(stateDir: dir, probe: probe)
    }

    // Portless loads routes with a probe that counts EPERM as dead, but checks the
    // proxy with one that counts EPERM as alive (a sudo-started proxy is root-owned).
    static func readRoutes(stateDir: URL, probe: PidProbe) -> [Route] {
        guard let data = try? Data(contentsOf: stateDir.appendingPathComponent("routes.json")) else { return [] }
        return parseRoutes(data).filter { $0.pid == 0 || probe($0.pid) == .running }
    }

    static func readProxy(stateDir: URL, probe: PidProbe) -> ProxyState? {
        guard let port = readInt(stateDir.appendingPathComponent("proxy.port")),
              let pid = readInt(stateDir.appendingPathComponent("proxy.pid")),
              pid > 0, probe(pid_t(truncatingIfNeeded: pid)) != .gone
        else { return nil }
        let tls = FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("proxy.tls").path)
        return ProxyState(port: port, tls: tls)
    }

    public static func parseRoutes(_ data: Data) -> [Route] {
        (try? JSONDecoder().decode([LossyRoute].self, from: data))?.compactMap(\.route) ?? []
    }

    private static func readInt(_ url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct LossyRoute: Decodable {
    let route: Route?

    init(from decoder: Decoder) throws {
        route = try? Route(from: decoder)
    }
}
