import Foundation

// Per-namespace data, written to namespaces.json.

struct PodSnapshot: Codable, Hashable, Identifiable {
    var name: String
    var status: String  // "Running" or the problem reason (CrashLoopBackOff, Pending, NotReady…)
    var ready: Bool
    var restarts: Int
    var cpu: Double?  // millicores
    var mem: Double?  // bytes
    var id: String { name }
}

struct WorkloadSnapshot: Codable, Hashable, Identifiable {
    var kind: String  // "deploy" | "sts"
    var name: String
    var ready: Int
    var desired: Int
    var id: String { kind + "/" + name }
}

struct NamespaceSnapshot: Codable, Hashable, Identifiable {
    var context: String
    var name: String
    var podsTotal = 0, podsRunning = 0, podsBad = 0, restarts = 0
    var cpuUsed: Double? = nil, memUsed: Double? = nil
    var cpuRequests = 0.0, memRequests = 0.0, cpuLimits = 0.0, memLimits = 0.0
    var workloads: [WorkloadSnapshot] = []
    var pods: [PodSnapshot] = []  // worst/busiest first, capped
    var cpuHistory: [Double]? = nil, memHistory: [Double]? = nil  // absolute (millicores / bytes)

    var id: String { context + "|" + name }
    var clusterShortName: String { shortContextName(context) }
    var workloadsReady: Int { workloads.filter { $0.desired > 0 && $0.ready >= $0.desired }.count }
    var workloadsActive: Int { workloads.filter { $0.desired > 0 }.count }
    var healthy: Bool { podsBad == 0 && workloadsReady == workloadsActive }

    /// Usage relative to limits if set, else requests. nil when neither is set.
    var cpuFrac: Double? { frac(cpuUsed, cpuLimits > 0 ? cpuLimits : cpuRequests) }
    var memFrac: Double? { frac(memUsed, memLimits > 0 ? memLimits : memRequests) }

    private func frac(_ used: Double?, _ of: Double) -> Double? {
        guard let used, of > 0 else { return nil }
        return used / of
    }
}

struct NamespaceFile: Codable {
    var updated: Date
    var namespaces: [NamespaceSnapshot]
}
