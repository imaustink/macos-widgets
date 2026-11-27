import Foundation

// SSH hosts from ~/.ssh/config, written by the host app and read by the "SSH" widget.

struct SSHHost: Codable, Identifiable, Hashable {
    var alias: String
    var hostname: String
    var user: String?
    var port: Int
    var jump: String?        // ProxyJump / ProxyCommand target, if any
    var reachable: Bool?     // nil = not checked (behind a jump host) or not yet probed
    var latencyMs: Int?
    var reason: String?      // why it's unreachable: "timeout", "refused", "no route", "DNS failed", "blocked"

    var id: String { alias }

    /// "ubuntu@10.0.0.31" (port shown only when non-default).
    var target: String {
        let u = user.map { "\($0)@" } ?? ""
        return u + hostname + (port == 22 ? "" : ":\(port)")
    }
}

struct SSHFile: Codable {
    var updated: Date
    var hosts: [SSHHost]

    static let empty = SSHFile(updated: .distantPast, hosts: [])
    static let placeholder = SSHFile(updated: .now, hosts: [
        SSHHost(alias: "bastion", hostname: "10.0.0.10", user: "admin", port: 22, reachable: true, latencyMs: 3),
        SSHHost(alias: "db1", hostname: "10.0.0.21", user: "ubuntu", port: 22, reachable: true, latencyMs: 4),
        SSHHost(alias: "kube0", hostname: "10.0.0.31", user: "ubuntu", port: 22, reachable: true, latencyMs: 2),
        SSHHost(alias: "printcam", hostname: "10.0.0.40", user: "pi", port: 22, reachable: false, reason: "timeout"),
        SSHHost(alias: "web", hostname: "203.0.113.7", user: "bitnami", port: 22, reachable: true, latencyMs: 41),
        SSHHost(alias: "nas", hostname: "10.0.0.2", user: "admin", port: 2222, jump: "bastion"),
    ])
}
