import Foundation
import Network
import WidgetKit

// Reads ~/.ssh/config (following Include), resolves each alias with `ssh -G`,
// and TCP-probes port 22 (or whatever the host uses) every minute.

private let home = FileManager.default.homeDirectoryForCurrentUser.path

/// Host aliases in config order, following Include. Wildcard patterns are skipped.
func sshAliases(file: String = "\(home)/.ssh/config", seen: inout Set<String>) -> [String] {
    guard !seen.contains(file), let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
    seen.insert(file)
    var out: [String] = []
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.hasPrefix("#"), !line.isEmpty else { continue }
        let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
        guard parts.count == 2 else { continue }
        let key = parts[0].lowercased()
        let args = parts[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if key == "host" {
            out += args.filter { !$0.contains(where: { "*?!".contains($0) }) }
        } else if key == "include" {
            for pattern in args {
                var p = (pattern as NSString).expandingTildeInPath
                if !p.hasPrefix("/") { p = "\(home)/.ssh/\(p)" }
                for f in globPaths(p) { out += sshAliases(file: f, seen: &seen) }
            }
        }
    }
    return out
}

private func globPaths(_ pattern: String) -> [String] {
    var g = glob_t()
    defer { globfree(&g) }
    guard glob(pattern, 0, nil, &g) == 0 else { return [] }
    return (0..<Int(g.gl_matchc)).compactMap { g.gl_pathv[$0].flatMap { String(cString: $0) } }
}

/// Effective settings for an alias, as ssh itself would use them.
func resolveSSH(_ alias: String) async -> SSHHost? {
    let r = await sh("ssh", ["-G", alias], timeout: 5)
    guard r.code == 0 else { return nil }
    var kv: [String: String] = [:]
    for line in r.out.split(separator: "\n") {
        let p = line.split(separator: " ", maxSplits: 1)
        if p.count == 2, kv[String(p[0])] == nil { kv[String(p[0])] = String(p[1]) }
    }
    var jump: String?
    if let j = kv["proxyjump"], j != "none" { jump = j }
    else if let c = kv["proxycommand"], c != "none" { jump = "proxy" }
    return SSHHost(alias: alias,
                   hostname: kv["hostname"] ?? alias,
                   user: kv["user"],
                   port: Int(kv["port"] ?? "") ?? 22,
                   jump: jump)
}

/// TCP connect to host:port. Returns latency in ms, or nil if unreachable within the timeout.
func tcpProbe(host: String, port: Int, timeout: TimeInterval = 2.5) async -> Int? {
    guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
    let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
    let start = Date()
    return await withCheckedContinuation { cont in
        let once = ResumeOnce()
        let finish: @Sendable (Int?) -> Void = { v in
            if once.claim() { conn.cancel(); cont.resume(returning: v) }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(Int(Date().timeIntervalSince(start) * 1000))
            case .failed, .cancelled: finish(nil)
            case .waiting: finish(nil)   // no route / refused
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
    }
}

/// Guards a continuation that several callbacks race to resume.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

@MainActor
final class SSHMonitor: ObservableObject {
    @Published var hosts: [SSHHost] = Stores.ssh.load()?.hosts ?? []
    private var timer: Timer?
    private var lastSignature = ""

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh(force: Bool = false) async {
        var seen = Set<String>()
        var aliases: [String] = []
        for a in sshAliases(seen: &seen) where !aliases.contains(a) { aliases.append(a) }

        let resolved: [SSHHost] = await withTaskGroup(of: (Int, SSHHost?).self) { g in
            for (i, a) in aliases.enumerated() { g.addTask { (i, await resolveSSH(a)) } }
            var out = [(Int, SSHHost)]()
            for await (i, h) in g { if let h { out.append((i, h)) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // Git forges aren't shells; leave them out.
        let shells = resolved.filter { $0.user != "git" }

        let probed: [SSHHost] = await withTaskGroup(of: (Int, SSHHost).self) { g in
            for (i, h) in shells.enumerated() {
                g.addTask {
                    var h = h
                    if h.jump == nil {
                        h.latencyMs = await tcpProbe(host: h.hostname, port: h.port)
                        h.reachable = h.latencyMs != nil
                    }
                    return (i, h)
                }
            }
            var out = [(Int, SSHHost)]()
            for await r in g { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // Jump hosts inherit their bastion's reachability.
        let byAlias = Dictionary(probed.map { ($0.alias, $0) }, uniquingKeysWith: { a, _ in a })
        hosts = probed.map { h in
            var h = h
            if let j = h.jump, let b = byAlias[j.split(separator: ",").first.map(String.init) ?? j] {
                h.reachable = b.reachable
            }
            return h
        }

        Stores.ssh.save(SSHFile(updated: .now, hosts: hosts))
        // Latency jitters every poll; only reload the widget when the up/down picture changes.
        let sig = hosts.map { "\($0.alias)=\($0.reachable.map { $0 ? "1" : "0" } ?? "?")" }.joined(separator: ",")
        if force || sig != lastSignature {
            lastSignature = sig
            WidgetCenter.shared.reloadTimelines(ofKind: "SSH")
        }
    }
}
