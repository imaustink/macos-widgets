import AppIntents
import SwiftUI
import WidgetKit

// "Cluster": one context you pick in Edit Widget. Click to open k9s on it.

struct ClusterEntity: AppEntity {
    let id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cluster"
    static var defaultQuery = ClusterQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(shortContextName(id))")
    }
}

struct ClusterQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ClusterEntity] {
        identifiers.map(ClusterEntity.init)
    }

    func suggestedEntities() async throws -> [ClusterEntity] {
        (Stores.snapshot.load()?.clusters ?? []).map { ClusterEntity(id: $0.name) }
    }

    func defaultResult() async -> ClusterEntity? {
        let clusters = Stores.snapshot.load()?.clusters ?? []
        return (clusters.first { $0.status != .down } ?? clusters.first).map { ClusterEntity(id: $0.name) }
    }
}

struct SelectClusterIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Cluster"
    static var description = IntentDescription("Pick which kube context this widget shows.")

    @Parameter(title: "Cluster")
    var cluster: ClusterEntity?
}

struct ClusterEntry: TimelineEntry {
    let date: Date
    let cluster: ClusterSnapshot?
    let configuredName: String?
    var signingIn = false
}

struct ClusterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClusterEntry {
        ClusterEntry(date: .now, cluster: Snapshot.placeholder.clusters[0], configuredName: "homelab")
    }

    func snapshot(for configuration: SelectClusterIntent, in context: Context) async -> ClusterEntry {
        let e = entry(for: configuration)
        if e.cluster == nil && context.isPreview { return placeholder(in: context) }
        return e
    }

    func timeline(for configuration: SelectClusterIntent, in context: Context) async -> Timeline<ClusterEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(900)))
    }

    private func entry(for config: SelectClusterIntent) -> ClusterEntry {
        let snap = Stores.snapshot.load()
        let clusters = snap?.clusters ?? []
        let name = config.cluster?.id
            ?? clusters.first(where: { $0.status != .down })?.name
            ?? clusters.first?.name
        let c = clusters.first { $0.name == name }
        return ClusterEntry(date: .now, cluster: c, configuredName: name,
                            signingIn: c.map { snap?.signingIn($0) ?? false } ?? false)
    }
}

struct ClusterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Cluster", intent: SelectClusterIntent.self, provider: ClusterProvider()) { entry in
            ClusterView(entry: entry)
        }
        .configurationDisplayName("Cluster")
        .description("CPU, memory and pods for one context. Click to open k9s.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClusterView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClusterEntry

    var body: some View {
        Group {
            if let c = entry.cluster {
                switch family {
                case .systemSmall: small(c)
                case .systemLarge: ClusterDetail(cluster: c, signingIn: entry.signingIn, maxNodes: 12, maxIssues: 4, sparkHeight: 20)
                default: medium(c)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "helm").font(.title2)
                    Text(entry.configuredName.map(shortContextName) ?? "No cluster")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Waiting for KubeWidget.app…")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(tapURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var tapURL: URL? {
        if let c = entry.cluster, c.needsSSO, let p = c.awsProfile { return ssoURL(profile: p) }
        return entry.configuredName.map { k9sURL(for: $0) }
    }

    @ViewBuilder private func action(_ c: ClusterSnapshot) -> some View {
        if c.needsSSO { SSOBadge(signingIn: entry.signingIn) } else { K9sBadge() }
    }

    private func title(_ c: ClusterSnapshot) -> some View {
        HStack(spacing: 6) {
            StatusDot(status: c.status, size: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(c.shortName).font(.system(size: 13, weight: .bold)).lineLimit(1)
                if let sub = c.subtitle {
                    Text(sub).font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func podsLine(_ c: ClusterSnapshot) -> some View {
        HStack(spacing: 4) {
            Text("\(c.nodesReady)/\(c.nodesTotal) nodes · \(c.podsRunning) pods")
                .foregroundStyle(.secondary)
            if c.podsBad > 0 {
                Text("· \(c.podsBad) bad").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .lineLimit(1)
    }

    private func small(_ c: ClusterSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title(c)
            if c.status == .down {
                Spacer()
                Text(c.reason ?? "down").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer(minLength: 0)
                MiniBar(label: "CPU", frac: c.cpuFrac)
                MiniBar(label: "MEM", frac: c.memFrac)
                podsLine(c)
                Spacer(minLength: 0)
            }
            action(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ c: ClusterSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                title(c)
                Spacer(minLength: 0)
                if c.status == .down {
                    Text(c.reason ?? "down").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    podsLine(c)
                    if let u = c.cpuUsed, let m = c.memUsed {
                        Text("\(fmtCores(u))/\(fmtCores(c.cpuAlloc)) cores · \(fmtBytes(m))/\(fmtBytes(c.memAlloc))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                action(c)
            }
            if c.status != .down {
                Ring(label: "CPU", frac: c.cpuFrac).frame(width: 62, height: 62)
                Ring(label: "MEM", frac: c.memFrac).frame(width: 62, height: 62)
            }
        }
    }
}
