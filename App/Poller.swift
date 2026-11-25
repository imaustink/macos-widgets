import Foundation
import WidgetKit

// Polls every visible context once a minute and publishes snapshots for the widgets.

@MainActor
final class Poller: ObservableObject {
    @Published var clusters: [ClusterSnapshot] = []
    @Published var allContexts: [String] = []
    @Published var refreshing = false
    @Published var lastUpdated: Date?
    @Published var ssoInProgress: Set<String> = []
    @Published var ssoError: String?
    @Published var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hidden") ?? []) {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: "hidden") }
    }

    private var timer: Timer?
    private var history: [String: (cpu: [Double], mem: [Double])] = [:]
    private var nsHistory: [String: (cpu: [Double], mem: [Double])] = [:]

    init() {
        // Carry sparkline history across app restarts.
        for c in Stores.snapshot.load()?.clusters ?? [] {
            history[c.name] = (c.cpuHistory ?? [], c.memHistory ?? [])
        }
        for n in Stores.namespaces.load()?.namespaces ?? [] {
            nsHistory[n.id] = (n.cpuHistory ?? [], n.memHistory ?? [])
        }
    }
    private var lastReload = Date.distantPast
    private var lastSignature = ""
    private var lastMetrics = ""

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh(force: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let r = await sh("kubectl", ["config", "get-contexts", "-o", "name"])
        let names = r.out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        allContexts = names
        let targets = names.filter { !hidden.contains($0) }

        let profiles = await awsProfilesByContext()
        var results: [String: ClusterSnapshot] = [:]
        var namespaces: [NamespaceSnapshot] = []
        await withTaskGroup(of: ProbeResult.self) { group in
            for n in targets {
                group.addTask {
                    var r = await probe(n)
                    r.cluster.awsProfile = profiles[n]
                    return r
                }
            }
            for await r in group {
                results[r.cluster.name] = r.cluster
                namespaces += r.namespaces
            }
        }
        // Keep the last-known namespaces of clusters that are temporarily down.
        let fresh = Set(namespaces.map(\.context))
        let previous = Stores.namespaces.load()?.namespaces ?? []
        namespaces += previous.filter { !fresh.contains($0.context) && targets.contains($0.context) }
        namespaces = namespaces.map { n in
            var n = n
            guard fresh.contains(n.context) else { return n }
            var h = nsHistory[n.id] ?? ([], [])
            if let c = n.cpuUsed { h.cpu = Array((h.cpu + [c]).suffix(historyLength)) }
            if let m = n.memUsed { h.mem = Array((h.mem + [m]).suffix(historyLength)) }
            nsHistory[n.id] = h
            n.cpuHistory = h.cpu
            n.memHistory = h.mem
            return n
        }
        Stores.namespaces.save(NamespaceFile(updated: .now, namespaces: namespaces))
        clusters = targets.compactMap { n -> ClusterSnapshot? in
            guard var c = results[n] else { return nil }
            var h = history[n] ?? ([], [])
            if let f = c.cpuFrac { h.cpu = Array((h.cpu + [f]).suffix(historyLength)) }
            if let f = c.memFrac { h.mem = Array((h.mem + [f]).suffix(historyLength)) }
            history[n] = h
            c.cpuHistory = h.cpu
            c.memHistory = h.mem
            return c
        }
        lastUpdated = .now
        publish(force: force)
    }

    /// Runs `aws sso login` (opens the browser, waits for approval), then re-probes everything.
    func ssoLogin(profile: String) async {
        guard !ssoInProgress.contains(profile) else { return }
        ssoInProgress.insert(profile)
        ssoError = nil
        publish(force: true)
        let r = await sh("aws", ["sso", "login", "--profile", profile], timeout: 600)
        ssoInProgress.remove(profile)
        if r.code != 0 {
            ssoError = "\(profile): " + classify(r.err.isEmpty ? r.out : r.err)
        }
        // A finished refresh may have been skipped while one was running; wait it out.
        while refreshing { try? await Task.sleep(for: .milliseconds(250)) }
        await refresh(force: true)
    }

    func ssoLoginAllExpired() async {
        let profiles = Set(clusters.filter(\.needsSSO).compactMap(\.awsProfile))
        await withTaskGroup(of: Void.self) { g in
            for p in profiles { g.addTask { await self.ssoLogin(profile: p) } }
        }
    }

    func toggleHidden(_ name: String) {
        if hidden.contains(name) { hidden.remove(name) } else { hidden.insert(name) }
        Task { await refresh(force: true) }
    }

    /// Writes the snapshot for the widget, and asks WidgetKit to reload only when something
    /// visible changed (or every 5 min) so we stay inside the background reload budget.
    private func publish(force: Bool) {
        Stores.snapshot.save(Snapshot(updated: lastUpdated ?? .now, clusters: clusters,
                                    ssoInProgress: Array(ssoInProgress)))
        // macOS gives widgets a daily reload budget; once spent, they freeze on stale data.
        // So reload right away only for structural changes (contexts, health, SSO), and at most
        // every 15 minutes when only the numbers moved.
        let structure = clusters.map { c in
            "\(c.name)|\(c.status)|\(c.reason ?? "")|\(c.nodesReady)/\(c.nodesTotal)|\(c.podsBad)|"
                + "\(c.workloadsReady ?? 0)/\(c.workloadsTotal ?? 0)"
        }.joined(separator: ";") + "|sso:" + ssoInProgress.sorted().joined(separator: ",")
        let metrics = clusters.map { c in
            "\(Int((c.cpuFrac ?? -1) * 10))/\(Int((c.memFrac ?? -1) * 10))"
        }.joined(separator: ";")
        let metricsDue = metrics != lastMetrics && Date().timeIntervalSince(lastReload) > 900
        if force || structure != lastSignature || metricsDue {
            lastSignature = structure
            lastMetrics = metrics
            lastReload = .now
            for kind in ["Clusters", "Cluster", "Namespace"] {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }
}
