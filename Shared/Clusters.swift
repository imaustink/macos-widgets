import Foundation

// Per-context cluster data, written to snapshot.json.

let historyLength = 60  // sparkline samples (one per poll, ~1h)

enum ClusterStatus: String, Codable { case up, degraded, down }

struct NodeSnapshot: Codable, Hashable, Identifiable {
    var name: String
    var ready: Bool
    var controlPlane: Bool
    var cpuFrac: Double?
    var memFrac: Double?
    var id: String { name }
}

struct PodIssue: Codable, Hashable, Identifiable {
    var namespace: String
    var name: String
    var reason: String
    var restarts: Int
    var id: String { namespace + "/" + name }
}

struct ClusterSnapshot: Codable, Hashable, Identifiable {
    var name: String
    var status: ClusterStatus
    var reason: String?
    var nodesReady = 0, nodesTotal = 0
    var podsRunning = 0, podsBad = 0
    var cpuUsed: Double? = nil, cpuAlloc = 0.0  // millicores
    var memUsed: Double? = nil, memAlloc = 0.0  // bytes
    var awsProfile: String? = nil  // from the kubeconfig exec env/args, for EKS contexts

    // Rich details. Optional so older snapshot files still decode.
    var version: String? = nil
    var nodes: [NodeSnapshot]? = nil
    var issues: [PodIssue]? = nil  // worst few unhealthy pods; podsBad is the full count
    var restarts: Int? = nil
    var workloadsReady: Int? = nil, workloadsTotal: Int? = nil
    var cpuHistory: [Double]? = nil, memHistory: [Double]? = nil

    /// "v1.31.1+k3s1" -> "v1.31.1 · k3s", "v1.30.4-eks-a737599" -> "v1.30.4 · eks"
    var versionLabel: String? {
        guard let v = version else { return nil }
        let parts = v.split(whereSeparator: { $0 == "+" || $0 == "-" })
        guard let base = parts.first else { return v }
        guard parts.count > 1 else { return String(base) }
        let distro = String(parts[1]).trimmingCharacters(in: .decimalDigits)
        return distro.isEmpty ? String(base) : "\(base) · \(distro)"
    }

    var id: String { name }

    /// Down because the AWS SSO token is missing/expired, and we know which profile to log in.
    var needsSSO: Bool {
        status == .down && awsProfile != nil && (reason == "SSO expired" || reason == "AWS auth failed")
    }
    var shortName: String { shortContextName(name) }

    var subtitle: String? {
        guard name.hasPrefix("arn:aws:eks:") else { return nil }
        let parts = name.split(separator: ":")
        return parts.count > 3 ? "EKS · \(parts[3])" : "EKS"
    }

    var cpuFrac: Double? {
        guard let u = cpuUsed, cpuAlloc > 0 else { return nil }
        return u / cpuAlloc
    }

    var memFrac: Double? {
        guard let u = memUsed, memAlloc > 0 else { return nil }
        return u / memAlloc
    }
}

struct Snapshot: Codable {
    var updated: Date
    var clusters: [ClusterSnapshot]
    var ssoInProgress: [String]? = nil  // AWS profiles currently running `aws sso login`

    func signingIn(_ c: ClusterSnapshot) -> Bool {
        c.awsProfile.map { ssoInProgress?.contains($0) == true } ?? false
    }

    static let empty = Snapshot(updated: .distantPast, clusters: [])

    static let placeholder = Snapshot(updated: .now, clusters: [
        ClusterSnapshot(name: "homelab", status: .up, nodesReady: 3, nodesTotal: 3, podsRunning: 84,
                        cpuUsed: 1800, cpuAlloc: 12000, memUsed: 13.2e9, memAlloc: 24e9),
        ClusterSnapshot(name: "arn:aws:eks:us-east-1:000:cluster/platform", status: .degraded,
                        nodesReady: 5, nodesTotal: 6, podsRunning: 212, podsBad: 3,
                        cpuUsed: 14000, cpuAlloc: 24000, memUsed: 70e9, memAlloc: 96e9),
        ClusterSnapshot(name: "minikube", status: .down, reason: "offline"),
    ])
}

/// arn:aws:eks:us-east-1:123:cluster/foo -> foo, admin@cluster -> cluster
func shortContextName(_ name: String) -> String {
    if name.hasPrefix("arn:"), let last = name.split(separator: "/").last { return String(last) }
    if let at = name.firstIndex(of: "@") { return String(name[name.index(after: at)...]) }
    return name
}
