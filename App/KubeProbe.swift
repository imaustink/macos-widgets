import Foundation

// Probing a kube context with kubectl and turning the output into snapshots.

func parseCPU(_ s: String) -> Double {  // -> millicores
    if s.hasSuffix("m") { return Double(s.dropLast()) ?? 0 }
    if s.hasSuffix("n") { return (Double(s.dropLast()) ?? 0) / 1_000_000 }
    return (Double(s) ?? 0) * 1000
}

func parseMem(_ s: String) -> Double {  // -> bytes
    let units: [(String, Double)] = [
        ("Ki", 1024), ("Mi", pow(1024, 2)), ("Gi", pow(1024, 3)), ("Ti", pow(1024, 4)),
        ("k", 1e3), ("K", 1e3), ("M", 1e6), ("G", 1e9), ("T", 1e12),
    ]
    for (u, m) in units where s.hasSuffix(u) {
        return (Double(s.dropLast(u.count)) ?? 0) * m
    }
    return Double(s) ?? 0
}

func classify(_ err: String) -> String {
    let e = err.lowercased()
    if e.contains("sso") || e.contains("token has expired") { return "SSO expired" }
    if e.contains("executable aws failed") { return "AWS auth failed" }
    if e.contains("no route to host") || e.contains("network is unreachable") { return "no route" }
    if e.contains("refused") { return "offline" }
    if e.contains("timeout") || e.contains("deadline") { return "timeout" }
    if e.contains("forbidden") || e.contains("unauthorized") { return "unauthorized" }
    if e.contains("no such host") { return "DNS failed" }
    let line = err.split(separator: "\n").last.map(String.init) ?? err
    return String(line.suffix(40))
}

private struct NodeList: Decodable {
    let items: [Node]
    struct Node: Decodable {
        let metadata: Meta
        let status: Status
        struct Meta: Decodable { let name: String; let labels: [String: String]? }
        struct Status: Decodable {
            let allocatable: [String: String]?
            let conditions: [Cond]?
            let nodeInfo: Info?
        }
        struct Cond: Decodable { let type: String; let status: String }
        struct Info: Decodable { let kubeletVersion: String? }
    }
}

private struct KubeConfig: Decodable {
    let contexts: [Ctx]?
    let users: [User]?
    struct Ctx: Decodable { let name: String; let context: Inner?; struct Inner: Decodable { let user: String? } }
    struct User: Decodable {
        let name: String
        let user: Auth?
        struct Auth: Decodable { let exec: Exec? }
        struct Exec: Decodable {
            let args: [String]?
            let env: [Env]?
            struct Env: Decodable { let name: String; let value: String }
        }
    }
}

/// context name -> AWS profile used by its `aws eks get-token` exec plugin (env AWS_PROFILE or --profile).
func awsProfilesByContext() async -> [String: String] {
    let r = await sh("kubectl", ["config", "view", "-o", "json"])
    guard r.code == 0, let cfg = try? JSONDecoder().decode(KubeConfig.self, from: Data(r.out.utf8)) else { return [:] }
    var byUser: [String: String] = [:]
    for u in cfg.users ?? [] {
        guard let exec = u.user?.exec else { continue }
        if let p = exec.env?.first(where: { $0.name == "AWS_PROFILE" })?.value {
            byUser[u.name] = p
        } else if let args = exec.args, let i = args.firstIndex(of: "--profile"), i + 1 < args.count {
            byUser[u.name] = args[i + 1]
        }
    }
    var out: [String: String] = [:]
    for c in cfg.contexts ?? [] {
        if let user = c.context?.user, let p = byUser[user] { out[c.name] = p }
    }
    return out
}

struct ProbeResult {
    var cluster: ClusterSnapshot
    var namespaces: [NamespaceSnapshot]
}

private func sumList(_ s: String, _ parse: (String) -> Double) -> Double {
    s == "<none>" ? 0 : s.split(separator: ",").map { parse(String($0)) }.reduce(0, +)
}

func probe(_ ctx: String) async -> ProbeResult {
    let base = ["--context", ctx, "--request-timeout=8s"]
    async let nodesR = sh("kubectl", base + ["get", "nodes", "-o", "json"])
    async let topR = sh("kubectl", base + ["top", "nodes", "--no-headers"])
    async let topPodsR = sh("kubectl", base + ["top", "pods", "-A", "--no-headers"])
    async let podsR = sh("kubectl", base + [
        "get", "pods", "-A", "--no-headers", "-o",
        "custom-columns=NS:.metadata.namespace,N:.metadata.name,P:.status.phase,"
            + "R:.status.containerStatuses[*].ready,RS:.status.containerStatuses[*].restartCount,"
            + "W:.status.containerStatuses[*].state.waiting.reason,"
            + "RC:.spec.containers[*].resources.requests.cpu,RM:.spec.containers[*].resources.requests.memory,"
            + "LC:.spec.containers[*].resources.limits.cpu,LM:.spec.containers[*].resources.limits.memory",
    ])
    async let workR = sh("kubectl", base + [
        "get", "deploy,sts", "-A", "--no-headers", "-o",
        "custom-columns=NS:.metadata.namespace,K:.kind,N:.metadata.name,D:.spec.replicas,R:.status.readyReplicas",
    ])

    let nodes = await nodesR
    guard nodes.code == 0,
          let list = try? JSONDecoder().decode(NodeList.self, from: Data(nodes.out.utf8))
    else {
        _ = await topR; _ = await topPodsR; _ = await podsR; _ = await workR
        return ProbeResult(
            cluster: ClusterSnapshot(name: ctx, status: .down,
                                     reason: classify(nodes.err.isEmpty ? nodes.out : nodes.err)),
            namespaces: [])
    }

    var s = ClusterSnapshot(name: ctx, status: .up)
    s.nodesTotal = list.items.count
    s.version = list.items.first?.status.nodeInfo?.kubeletVersion
    var nodeSnaps: [NodeSnapshot] = []
    for n in list.items {
        let ready = n.status.conditions?.contains(where: { $0.type == "Ready" && $0.status == "True" }) == true
        if ready { s.nodesReady += 1 }
        s.cpuAlloc += parseCPU(n.status.allocatable?["cpu"] ?? "0")
        s.memAlloc += parseMem(n.status.allocatable?["memory"] ?? "0")
        let labels = n.metadata.labels ?? [:]
        let cp = labels["node-role.kubernetes.io/control-plane"] != nil || labels["node-role.kubernetes.io/master"] != nil
        nodeSnaps.append(NodeSnapshot(name: n.metadata.name, ready: ready, controlPlane: cp))
    }

    let top = await topR
    if top.code == 0 {
        var cpu = 0.0, mem = 0.0
        for line in top.out.split(separator: "\n") {
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard cols.count >= 5 else { continue }
            cpu += parseCPU(cols[1])
            mem += parseMem(cols[3])
            if let i = nodeSnaps.firstIndex(where: { $0.name == cols[0] }) {
                nodeSnaps[i].cpuFrac = Double(cols[2].dropLast()).map { $0 / 100 }
                nodeSnaps[i].memFrac = Double(cols[4].dropLast()).map { $0 / 100 }
            }
        }
        s.cpuUsed = cpu
        s.memUsed = mem
    }
    s.nodes = nodeSnaps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    // Per-pod usage, keyed "ns/name".
    var podUsage: [String: (cpu: Double, mem: Double)] = [:]
    let topPods = await topPodsR
    for line in topPods.code == 0 ? topPods.out.split(separator: "\n") : [] {
        let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard cols.count >= 4 else { continue }
        podUsage["\(cols[0])/\(cols[1])"] = (parseCPU(cols[2]), parseMem(cols[3]))
    }

    var nsMap: [String: NamespaceSnapshot] = [:]
    var nsPods: [String: [PodSnapshot]] = [:]

    let pods = await podsR
    if pods.code == 0 {
        var issues: [PodIssue] = []
        var restarts = 0
        for line in pods.out.split(separator: "\n") {
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard cols.count >= 10 else { continue }
            let (ns, name, phase, ready) = (cols[0], cols[1], cols[2], cols[3])
            let r = cols[4].split(separator: ",").compactMap { Int($0) }.reduce(0, +)
            let waiting = cols[5].split(separator: ",").map(String.init).first { $0 != "<none>" }
            restarts += r
            if phase == "Succeeded" { continue }

            var problem: String?
            switch phase {
            case "Running" where !ready.contains("false"): s.podsRunning += 1
            case "Running": problem = waiting ?? "NotReady"
            default: problem = waiting ?? phase
            }
            if let p = problem {
                issues.append(PodIssue(namespace: ns, name: name, reason: p, restarts: r))
            }

            var n = nsMap[ns] ?? NamespaceSnapshot(context: ctx, name: ns)
            n.podsTotal += 1
            if problem == nil { n.podsRunning += 1 } else { n.podsBad += 1 }
            n.restarts += r
            n.cpuRequests += sumList(cols[6], parseCPU)
            n.memRequests += sumList(cols[7], parseMem)
            n.cpuLimits += sumList(cols[8], parseCPU)
            n.memLimits += sumList(cols[9], parseMem)
            nsMap[ns] = n
            let u = podUsage["\(ns)/\(name)"]
            nsPods[ns, default: []].append(PodSnapshot(
                name: name, status: problem ?? "Running", ready: problem == nil,
                restarts: r, cpu: u?.cpu, mem: u?.mem))
        }
        s.podsBad = issues.count
        s.restarts = restarts
        // Hard failures (CrashLoop, ImagePull, Failed…) before merely not-ready; then by restarts.
        s.issues = Array(issues.sorted {
            let a = $0.reason == "NotReady" ? 1 : 0, b = $1.reason == "NotReady" ? 1 : 0
            return a != b ? a < b : $0.restarts > $1.restarts
        }.prefix(8))
    }

    if topPods.code == 0 {
        for (key, u) in podUsage {
            let ns = String(key.prefix { $0 != "/" })
            guard var n = nsMap[ns] else { continue }
            n.cpuUsed = (n.cpuUsed ?? 0) + u.cpu
            n.memUsed = (n.memUsed ?? 0) + u.mem
            nsMap[ns] = n
        }
        for k in nsMap.keys where nsMap[k]?.cpuUsed == nil {
            nsMap[k]?.cpuUsed = 0
            nsMap[k]?.memUsed = 0
        }
    }

    let work = await workR
    if work.code == 0 {
        var ready = 0, total = 0
        for line in work.out.split(separator: "\n") {
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard cols.count >= 5 else { continue }
            let want = Int(cols[3]) ?? 0, have = Int(cols[4]) ?? 0
            if want > 0 {
                total += 1
                if have >= want { ready += 1 }
            }
            let kind = cols[1] == "StatefulSet" ? "sts" : "deploy"
            var n = nsMap[cols[0]] ?? NamespaceSnapshot(context: ctx, name: cols[0])
            n.workloads.append(WorkloadSnapshot(kind: kind, name: cols[2], ready: have, desired: want))
            nsMap[cols[0]] = n
        }
        s.workloadsReady = ready
        s.workloadsTotal = total
    }

    for (ns, list) in nsPods {
        // Problems first, then busiest.
        nsMap[ns]?.pods = Array(list.sorted {
            $0.ready != $1.ready ? !$0.ready : ($0.cpu ?? 0) > ($1.cpu ?? 0)
        }.prefix(14))
    }
    for k in nsMap.keys {
        nsMap[k]?.workloads.sort {
            let a = $0.desired > 0 && $0.ready < $0.desired, b = $1.desired > 0 && $1.ready < $1.desired
            return a != b ? a : $0.name < $1.name
        }
    }

    if s.nodesReady < s.nodesTotal || s.podsBad > 0 || (s.workloadsReady ?? 0) < (s.workloadsTotal ?? 0) {
        s.status = .degraded
    }
    return ProbeResult(cluster: s, namespaces: nsMap.values.sorted { $0.name < $1.name })
}

