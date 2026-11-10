import Foundation
import Testing
@testable import PortlessCore

private let liveProbe: PidProbe = { pid in
    switch pid {
    case 100, 200, 300, 900: .running
    case 400: .notPermitted
    default: .gone
    }
}

private let routesJSON = """
[
  {"hostname": "r1.storybook.rema.localhost", "port": 4684, "pid": 100},
  {"hostname": "klavio-forms.comfort.localhost", "port": 4120, "pid": 200,
   "registeredAt": 1794249628969, "childPgid": 54457, "childStartTime": "Mon Nov 9 18:40:29 2026"},
  {"hostname": "docker.comfort.localhost", "port": 4300, "pid": 0},
  {"hostname": "dead.rema.localhost", "port": 4400, "pid": 555},
  {"hostname": "rootowned.rema.localhost", "port": 4500, "pid": 400},
  {"hostname": "no-port.localhost", "pid": 100},
  "garbage",
  null
]
"""

private func makeStateDir(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, contents) in files {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    return dir
}

private let runningProxyFiles = ["proxy.port": "443\n", "proxy.pid": "900", "proxy.tls": "1"]

@Test func decodesRealShapedRoutesAndSkipsInvalidEntries() {
    let routes = StateReader.parseRoutes(Data(routesJSON.utf8))
    #expect(routes.map(\.hostname) == [
        "r1.storybook.rema.localhost",
        "klavio-forms.comfort.localhost",
        "docker.comfort.localhost",
        "dead.rema.localhost",
        "rootowned.rema.localhost",
    ])
    #expect(routes[1] == Route(hostname: "klavio-forms.comfort.localhost", port: 4120, pid: 200))
}

@Test(arguments: ["", "{not json", "{\"hostname\": \"a.localhost\", \"port\": 1, \"pid\": 1}"])
func malformedRoutesFileYieldsNoRoutes(contents: String) {
    #expect(StateReader.parseRoutes(Data(contents.utf8)).isEmpty)
}

@Test func keepsLiveAndAliasRoutesAndDropsDeadOrForeignPids() throws {
    let dir = try makeStateDir(runningProxyFiles.merging(["routes.json": routesJSON]) { $1 })
    let hosts = StateReader.snapshot(stateDir: dir, probe: liveProbe).urls.map(\.hostname)
    #expect(Set(hosts) == ["r1.storybook.rema.localhost", "klavio-forms.comfort.localhost", "docker.comfort.localhost"])
}

@Test func formsHTTPSURLWithoutDefaultPort() {
    #expect(ProxyState(port: 443, tls: true).url(for: "app.localhost")?.absoluteString == "https://app.localhost")
}

@Test func formsURLWithNonDefaultPort() {
    #expect(ProxyState(port: 1355, tls: false).url(for: "app.localhost")?.absoluteString == "http://app.localhost:1355")
    #expect(ProxyState(port: 8443, tls: true).url(for: "app.localhost")?.absoluteString == "https://app.localhost:8443")
    #expect(ProxyState(port: 443, tls: false).url(for: "app.localhost")?.absoluteString == "http://app.localhost:443")
}

@Test func plainHTTPOnPort80OmitsPort() throws {
    let dir = try makeStateDir(["proxy.port": "80", "proxy.pid": "900", "routes.json": routesJSON])
    let urls = StateReader.snapshot(stateDir: dir, probe: liveProbe).urls.map(\.url.absoluteString)
    #expect(urls.contains("http://klavio-forms.comfort.localhost"))
}

@Test func groupsByLabelBeforeTLD() throws {
    let dir = try makeStateDir(runningProxyFiles.merging(["routes.json": routesJSON]) { $1 })
    guard case .routes(let proxy, let groups) = StateReader.snapshot(stateDir: dir, probe: liveProbe) else {
        Issue.record("expected routes")
        return
    }
    #expect(proxy == ProxyState(port: 443, tls: true))
    #expect(groups.map(\.name) == ["comfort", "rema"])
    #expect(groups[0].urls.map(\.hostname) == ["docker.comfort.localhost", "klavio-forms.comfort.localhost"])
    #expect(groups[1].urls.map(\.url.absoluteString) == ["https://r1.storybook.rema.localhost"])
}

@Test func bareNameIsItsOwnProject() {
    let active = ActiveURL(route: Route(hostname: "notes-api.localhost", port: 4000, pid: 1), proxy: ProxyState(port: 443, tls: true))
    #expect(active?.project == "notes-api")
}

@Test func missingStateDirIsProxyDown() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(StateReader.snapshot(stateDir: dir, probe: liveProbe) == .proxyDown)
}

@Test func deadProxyPidIsProxyDown() throws {
    let dir = try makeStateDir(["proxy.port": "443", "proxy.pid": "555", "routes.json": routesJSON])
    #expect(StateReader.snapshot(stateDir: dir, probe: liveProbe) == .proxyDown)
}

@Test func rootOwnedProxyCountsAsRunning() throws {
    let dir = try makeStateDir(["proxy.port": "443", "proxy.pid": "400"])
    #expect(StateReader.snapshot(stateDir: dir, probe: liveProbe) == .noRoutes(ProxyState(port: 443, tls: false)))
}

@Test func runningProxyWithMalformedRoutesIsNoRoutes() throws {
    let dir = try makeStateDir(runningProxyFiles.merging(["routes.json": "[{]"]) { $1 })
    #expect(StateReader.snapshot(stateDir: dir, probe: liveProbe) == .noRoutes(ProxyState(port: 443, tls: true)))
}

@Test func stateDirPrefersEnvironmentOverride() throws {
    let home = try makeStateDir([:])
    let dir = StateReader.resolveStateDir(environment: ["PORTLESS_STATE_DIR": "/custom/state"], home: home, probe: liveProbe)
    #expect(dir.path == "/custom/state")
}

@Test func stateDirFallsBackToLegacyOnlyWhenItsProxyRuns() throws {
    let home = try makeStateDir([:])
    let legacy = try makeStateDir(runningProxyFiles)
    #expect(StateReader.resolveStateDir(environment: [:], home: home, legacyDir: legacy, probe: liveProbe) == legacy)

    let stoppedLegacy = try makeStateDir(["proxy.port": "443", "proxy.pid": "555"])
    let resolved = StateReader.resolveStateDir(environment: [:], home: home, legacyDir: stoppedLegacy, probe: liveProbe)
    #expect(resolved == home.appendingPathComponent(".portless"))
}
