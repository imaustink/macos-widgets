import Foundation

// Made-up data for README screenshots, so docs never show anyone's real clusters or hosts.

private var rng = SeededRandom(seed: 42)

/// Deterministic so screenshots don't churn between runs.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A random walk ending at `end`, `historyLength` samples long.
func walk(_ end: Double?, step: Double = 0.03, lo: Double = 0.01, hi: Double = 1) -> [Double] {
    guard let end else { return [] }
    var v = end, out: [Double] = []
    for _ in 0..<historyLength {
        out.append(v)
        v = min(hi, max(lo, v + Double.random(in: -step...step, using: &rng)))
    }
    return out.reversed()
}

/// Same, for absolute values (millicores / bytes).
func absWalk(_ end: Double?) -> [Double] {
    guard let end, end > 0 else { return [] }
    return walk(0.5, step: 0.04).map { $0 * 2 * end }
}

private func nodes(_ prefix: String, _ n: Int, cp: Int = 0, notReady: Set<Int> = []) -> [NodeSnapshot] {
    (0..<n).map { i in
        NodeSnapshot(name: "\(prefix)\(i)", ready: !notReady.contains(i), controlPlane: i < cp,
                     cpuFrac: notReady.contains(i) ? nil : Double.random(in: 0.08...0.62, using: &rng),
                     memFrac: notReady.contains(i) ? nil : Double.random(in: 0.25...0.78, using: &rng))
    }
}

private func cluster(_ name: String, status: ClusterStatus, version: String, nodes ns: [NodeSnapshot],
                     pods: Int, bad: Int = 0, cpu: Double, cores: Double, mem: Double, memTotal: Double,
                     workloads: (Int, Int), restarts: Int, issues: [PodIssue] = []) -> ClusterSnapshot {
    var c = ClusterSnapshot(name: name, status: status)
    c.version = version
    c.nodes = ns
    c.nodesTotal = ns.count
    c.nodesReady = ns.filter(\.ready).count
    c.podsRunning = pods
    c.podsBad = bad
    c.cpuAlloc = cores * 1000
    c.cpuUsed = cpu * c.cpuAlloc
    c.memAlloc = memTotal * pow(1024, 3)
    c.memUsed = mem * c.memAlloc
    c.workloadsReady = workloads.0
    c.workloadsTotal = workloads.1
    c.restarts = restarts
    c.issues = issues
    c.cpuHistory = walk(cpu)
    c.memHistory = walk(mem, step: 0.01)
    return c
}

enum Demo {
    static let snapshot: Snapshot = {
        var sso = ClusterSnapshot(name: "arn:aws:eks:eu-west-1:000000000000:cluster/staging", status: .down,
                                  reason: "SSO expired")
        sso.awsProfile = "staging"
        return Snapshot(updated: .now.addingTimeInterval(-25), clusters: [
            cluster("homelab", status: .degraded, version: "v1.31.1+k3s1",
                    nodes: nodes("node", 6, cp: 1, notReady: [4]), pods: 132, bad: 2,
                    cpu: 0.21, cores: 24, mem: 0.48, memTotal: 64, workloads: (58, 60), restarts: 214,
                    issues: [PodIssue(namespace: "media", name: "jellyfin-6d9f7c-x2kq", reason: "CrashLoopBackOff", restarts: 37),
                             PodIssue(namespace: "db", name: "postgres-1", reason: "Pending", restarts: 0)]),
            cluster("arn:aws:eks:us-east-1:000000000000:cluster/production", status: .up, version: "v1.30.4-eks-a737599",
                    nodes: nodes("ip-10-0-1-", 4), pods: 96, cpu: 0.34, cores: 16, mem: 0.62, memTotal: 64,
                    workloads: (41, 41), restarts: 12),
            cluster("kind-dev", status: .up, version: "v1.32.0",
                    nodes: nodes("dev-control-plane", 1, cp: 1), pods: 18, cpu: 0.09, cores: 10, mem: 0.31, memTotal: 16,
                    workloads: (9, 9), restarts: 0),
            sso,
        ])
    }()

    static let namespace: NamespaceSnapshot = {
        var n = NamespaceSnapshot(context: "homelab", name: "monitoring")
        n.workloads = [
            WorkloadSnapshot(kind: "deploy", name: "grafana", ready: 1, desired: 1),
            WorkloadSnapshot(kind: "deploy", name: "kube-state-metrics", ready: 1, desired: 1),
            WorkloadSnapshot(kind: "sts", name: "prometheus", ready: 1, desired: 1),
            WorkloadSnapshot(kind: "sts", name: "alertmanager", ready: 0, desired: 1),
        ]
        n.pods = [
            PodSnapshot(name: "alertmanager-0", status: "CrashLoopBackOff", ready: false, restarts: 14, cpu: 2, mem: 18e6),
            PodSnapshot(name: "prometheus-0", status: "Running", ready: true, restarts: 0, cpu: 182, mem: 1.4e9),
            PodSnapshot(name: "grafana-7c9d8b-tk2lq", status: "Running", ready: true, restarts: 1, cpu: 41, mem: 210e6),
            PodSnapshot(name: "kube-state-metrics-5f-9wz", status: "Running", ready: true, restarts: 0, cpu: 12, mem: 64e6),
            PodSnapshot(name: "node-exporter-4mx2p", status: "Running", ready: true, restarts: 0, cpu: 9, mem: 22e6),
            PodSnapshot(name: "node-exporter-8vq7d", status: "Running", ready: true, restarts: 0, cpu: 8, mem: 21e6),
            PodSnapshot(name: "node-exporter-c3rtn", status: "Running", ready: true, restarts: 0, cpu: 7, mem: 20e6),
        ]
        n.podsTotal = n.pods.count
        n.podsBad = n.pods.filter { !$0.ready }.count
        n.podsRunning = n.podsTotal - n.podsBad
        n.restarts = n.pods.map(\.restarts).reduce(0, +)
        n.cpuUsed = n.pods.compactMap(\.cpu).reduce(0, +)
        n.memUsed = n.pods.compactMap(\.mem).reduce(0, +)
        n.cpuRequests = 400; n.cpuLimits = 1500
        n.memRequests = 2.5e9; n.memLimits = 4e9
        n.cpuHistory = absWalk(n.cpuUsed)
        n.memHistory = absWalk(n.memUsed)
        return n
    }()

    static let ssh = SSHFile(updated: .now.addingTimeInterval(-20), hosts: [
        SSHHost(alias: "bastion", hostname: "203.0.113.10", user: "admin", port: 22, reachable: true, latencyMs: 24),
        SSHHost(alias: "nas", hostname: "10.0.0.5", user: "admin", port: 22, reachable: true, latencyMs: 3),
        SSHHost(alias: "node0", hostname: "10.0.0.20", user: "ubuntu", port: 22, reachable: true, latencyMs: 2),
        SSHHost(alias: "node1", hostname: "10.0.0.21", user: "ubuntu", port: 22, reachable: true, latencyMs: 2),
        SSHHost(alias: "node2", hostname: "10.0.0.22", user: "ubuntu", port: 22, reachable: true, latencyMs: 3),
        SSHHost(alias: "node3", hostname: "10.0.0.23", user: "ubuntu", port: 22, reachable: true, latencyMs: 2),
        SSHHost(alias: "node4", hostname: "10.0.0.24", user: "ubuntu", port: 22, reachable: false, reason: "timeout"),
        SSHHost(alias: "node5", hostname: "10.0.0.25", user: "ubuntu", port: 22, reachable: true, latencyMs: 3),
        SSHHost(alias: "pi-hole", hostname: "10.0.0.53", user: "pi", port: 22, reachable: true, latencyMs: 4),
        SSHHost(alias: "printer", hostname: "printer.local", user: "pi", port: 22, reachable: true, latencyMs: 9),
        SSHHost(alias: "db-replica", hostname: "10.1.0.12", user: "ubuntu", port: 22, jump: "bastion", reachable: true),
        SSHHost(alias: "web", hostname: "198.51.100.7", user: "deploy", port: 2222, reachable: true, latencyMs: 41),
    ])
}
