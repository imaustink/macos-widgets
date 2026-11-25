import AppIntents
import SwiftUI
import WidgetKit

// "Namespace": usage, requests/limits, workloads and pods for one namespace. Click → k9s in that namespace.

struct NamespaceEntity: AppEntity {
    let id: String  // "<context>|<namespace>"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Namespace"
    static var defaultQuery = NamespaceQuery()

    var context: String { String(id[..<(id.lastIndex(of: "|") ?? id.startIndex)]) }
    var namespace: String { id.lastIndex(of: "|").map { String(id[id.index(after: $0)...]) } ?? id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(namespace)", subtitle: "\(shortContextName(context))")
    }
}

struct NamespaceQuery: EntityStringQuery {
    private func all() -> [NamespaceEntity] {
        (Stores.namespaces.load()?.namespaces ?? [])
            .sorted { ($0.clusterShortName, $0.name) < ($1.clusterShortName, $1.name) }
            .map { NamespaceEntity(id: $0.id) }
    }

    func entities(for identifiers: [String]) async throws -> [NamespaceEntity] {
        identifiers.map(NamespaceEntity.init)
    }

    func entities(matching string: String) async throws -> [NamespaceEntity] {
        let q = string.lowercased()
        return all().filter { $0.id.lowercased().contains(q) }
    }

    func suggestedEntities() async throws -> [NamespaceEntity] { all() }

    func defaultResult() async -> NamespaceEntity? {
        defaultNamespace().map { NamespaceEntity(id: $0.id) }
    }
}

/// Busiest non-system namespace on a live cluster.
func defaultNamespace() -> NamespaceSnapshot? {
    let system: Set = ["kube-system", "kube-public", "kube-node-lease"]
    return (Stores.namespaces.load()?.namespaces ?? [])
        .filter { !system.contains($0.name) && $0.cpuUsed != nil }
        .max { ($0.cpuUsed ?? 0) < ($1.cpuUsed ?? 0) }
}

struct SelectNamespaceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Namespace"
    static var description = IntentDescription("Pick the cluster namespace to monitor.")

    @Parameter(title: "Namespace")
    var namespace: NamespaceEntity?
}

struct NamespaceEntry: TimelineEntry {
    let date: Date
    let ns: NamespaceSnapshot?
    let configuredID: String?
    var updated: Date?
}

struct NamespaceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NamespaceEntry {
        NamespaceEntry(date: .now, ns: .placeholder, configuredID: nil)
    }

    func snapshot(for configuration: SelectNamespaceIntent, in context: Context) async -> NamespaceEntry {
        let e = entry(for: configuration)
        return e.ns == nil && context.isPreview ? placeholder(in: context) : e
    }

    func timeline(for configuration: SelectNamespaceIntent, in context: Context) async -> Timeline<NamespaceEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(900)))
    }

    private func entry(for config: SelectNamespaceIntent) -> NamespaceEntry {
        let file = Stores.namespaces.load()
        let id = config.namespace?.id ?? defaultNamespace()?.id
        return NamespaceEntry(date: .now, ns: file?.namespaces.first { $0.id == id },
                              configuredID: id, updated: file?.updated)
    }
}

struct NamespaceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Namespace", intent: SelectNamespaceIntent.self, provider: NamespaceProvider()) { entry in
            NamespaceWidgetView(entry: entry)
        }
        .configurationDisplayName("Namespace")
        .description("Resources, workloads and pods in one namespace. Click to open k9s there.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NamespaceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NamespaceEntry

    var body: some View {
        Group {
            if let ns = entry.ns {
                switch family {
                case .systemSmall: NamespaceSmall(ns: ns)
                case .systemLarge: NamespaceLarge(ns: ns)
                default: NamespaceMedium(ns: ns)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up").font(.title2)
                    Text(entry.configuredID.map { NamespaceEntity(id: $0).namespace } ?? "No namespace")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Waiting for KubeWidget.app…").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(entry.ns.map { k9sURL(for: $0.context, namespace: $0.name) })
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

extension NamespaceSnapshot {
    static let placeholder: NamespaceSnapshot = {
        var n = NamespaceSnapshot(context: "homelab", name: "monitoring")
        n.podsTotal = 9; n.podsRunning = 8; n.podsBad = 1; n.restarts = 4
        n.cpuUsed = 420; n.memUsed = 2.1e9
        n.cpuRequests = 900; n.memRequests = 3e9; n.cpuLimits = 2000; n.memLimits = 4e9
        n.workloads = [WorkloadSnapshot(kind: "deploy", name: "grafana", ready: 0, desired: 1),
                       WorkloadSnapshot(kind: "sts", name: "prometheus", ready: 1, desired: 1)]
        n.pods = [PodSnapshot(name: "grafana-856dbc6c7b-xr2hz", status: "NotReady", ready: false, restarts: 4, cpu: 12, mem: 1.8e8),
                  PodSnapshot(name: "prometheus-0", status: "Running", ready: true, restarts: 0, cpu: 310, mem: 1.4e9)]
        n.cpuHistory = (0..<40).map { 380 + 60 * sin(Double($0) / 5) }
        n.memHistory = (0..<40).map { 2.0e9 + 1e8 * sin(Double($0) / 9) }
        return n
    }()
}

// MARK: - Views

private func nsColor(_ frac: Double?) -> Color { frac == nil ? .cyan : usageColor(frac) }

struct NamespaceHeader: View {
    let ns: NamespaceSnapshot
    var big = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: big ? 11 : 10))
                .foregroundStyle(ns.healthy ? Color.green : Color.orange)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(ns.name).font(.system(size: big ? 13 : 12, weight: .bold)).lineLimit(1)
                Text(ns.clusterShortName).font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "terminal").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

/// Label + current value + absolute sparkline.
struct ValueSpark: View {
    let label: String
    let value: String
    let history: [Double]
    let color: Color
    var detail: String? = nil
    var height: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(color)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Sparkline(values: history, color: color, absolute: true).frame(height: height)
        }
    }
}

/// Usage bar with tick marks for requests (white) and limits (red).
struct ResourceBar: View {
    let label: String
    let used: Double?
    let request: Double
    let limit: Double
    let fmt: (Double) -> String

    var body: some View {
        let u = used ?? 0
        let scale = max(u, request, limit, 1e-9) * 1.08
        HStack(spacing: 6) {
            Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(nsColor(limit > 0 ? u / limit : request > 0 ? u / request : nil))
                        .frame(width: max(3, w * u / scale))
                    if request > 0 {
                        Rectangle().fill(.primary.opacity(0.8)).frame(width: 1.5, height: 9).offset(x: w * request / scale - 0.75)
                    }
                    if limit > 0 {
                        Rectangle().fill(Color.red).frame(width: 1.5, height: 9).offset(x: w * limit / scale - 0.75)
                    }
                }
            }
            .frame(height: 5)
            (Text(used.map(fmt) ?? "–").bold()
                + Text(request > 0 ? " · req \(fmt(request))" : "").foregroundStyle(.secondary)
                + Text(limit > 0 ? " · lim \(fmt(limit))" : "").foregroundStyle(.secondary))
                .font(.system(size: 8, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

struct NamespaceStats: View {
    let ns: NamespaceSnapshot
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            stat("\(ns.podsRunning)/\(ns.podsTotal)", "pods", warn: ns.podsBad > 0)
            if ns.workloadsActive > 0 {
                stat("\(ns.workloadsReady)/\(ns.workloadsActive)", compact ? "ready" : "workloads",
                     warn: ns.workloadsReady < ns.workloadsActive)
            }
            if !compact, ns.restarts > 0 { stat(fmtCount(ns.restarts), "restarts") }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func stat(_ v: String, _ l: String, warn: Bool = false) -> some View {
        (Text(v).font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(warn ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            + Text(" " + l).font(.system(size: 8)).foregroundStyle(.secondary))
            .fixedSize()
    }
}

struct PodRow: View {
    let pod: PodSnapshot
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(pod.ready ? Color.green : Color.orange).frame(width: 5, height: 5).widgetAccentable()
            Text(pod.name).font(.system(size: 9, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 3)
            if !pod.ready, !compact {
                Text(pod.status).font(.system(size: 8, weight: .semibold)).foregroundStyle(.orange).lineLimit(1).fixedSize()
            }
            if !compact, pod.restarts > 0 {
                Text("↻\(fmtCount(pod.restarts))").font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).fixedSize()
            }
            Text(pod.cpu.map(fmtMilli) ?? "–")
                .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            if !compact {
                Text(pod.mem.map(fmtMem) ?? "–")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

struct WorkloadChip: View {
    let w: WorkloadSnapshot

    var body: some View {
        let bad = w.desired > 0 && w.ready < w.desired
        HStack(spacing: 4) {
            Text(w.kind).font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
            Text(w.name).font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 2)
            Text("\(w.ready)/\(w.desired)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(bad ? AnyShapeStyle(.orange) : AnyShapeStyle(w.desired == 0 ? .tertiary : .secondary))
                .fixedSize()
        }
    }
}

struct NamespaceSmall: View {
    let ns: NamespaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NamespaceHeader(ns: ns)
            ValueSpark(label: "CPU", value: ns.cpuUsed.map(fmtMilli) ?? "–", history: ns.cpuHistory ?? [],
                       color: nsColor(ns.cpuFrac), height: 16)
            ValueSpark(label: "MEM", value: ns.memUsed.map(fmtMem) ?? "–", history: ns.memHistory ?? [],
                       color: nsColor(ns.memFrac), height: 16)
            Spacer(minLength: 0)
            NamespaceStats(ns: ns, compact: true)
        }
    }
}

struct NamespaceMedium: View {
    let ns: NamespaceSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                NamespaceHeader(ns: ns)
                ValueSpark(label: "CPU", value: ns.cpuUsed.map(fmtMilli) ?? "–", history: ns.cpuHistory ?? [],
                           color: nsColor(ns.cpuFrac), height: 16)
                ValueSpark(label: "MEM", value: ns.memUsed.map(fmtMem) ?? "–", history: ns.memHistory ?? [],
                           color: nsColor(ns.memFrac), height: 16)
                Spacer(minLength: 0)
                NamespaceStats(ns: ns)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 3) {
                Text("PODS").font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
                ForEach(ns.pods.prefix(6)) { PodRow(pod: $0, compact: true) }
                if ns.podsTotal > 6 {
                    Text("+\(ns.podsTotal - 6) more").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct NamespaceLarge: View {
    let ns: NamespaceSnapshot

    var body: some View {
        let maxPods = ns.workloads.count > 4 ? 7 : 9
        VStack(alignment: .leading, spacing: 6) {
            NamespaceHeader(ns: ns, big: true)
            HStack(spacing: 12) {
                ValueSpark(label: "CPU", value: ns.cpuUsed.map(fmtMilli) ?? "–", history: ns.cpuHistory ?? [],
                           color: nsColor(ns.cpuFrac), height: 22)
                ValueSpark(label: "MEM", value: ns.memUsed.map(fmtMem) ?? "–", history: ns.memHistory ?? [],
                           color: nsColor(ns.memFrac), height: 22)
            }
            VStack(spacing: 4) {
                ResourceBar(label: "CPU", used: ns.cpuUsed, request: ns.cpuRequests, limit: ns.cpuLimits, fmt: fmtMilli)
                ResourceBar(label: "MEM", used: ns.memUsed, request: ns.memRequests, limit: ns.memLimits, fmt: fmtMem)
            }
            NamespaceStats(ns: ns)
            if !ns.workloads.isEmpty {
                let shown = Array(ns.workloads.prefix(6))
                Grid(horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { i in
                        GridRow {
                            WorkloadChip(w: shown[i])
                            if i + 1 < shown.count { WorkloadChip(w: shown[i + 1]) } else { Color.clear.frame(height: 1) }
                        }
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ns.pods.prefix(maxPods)) { PodRow(pod: $0) }
                if ns.podsTotal > maxPods {
                    Text("+\(ns.podsTotal - maxPods) more pods").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
