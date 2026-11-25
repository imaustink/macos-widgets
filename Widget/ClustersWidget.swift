import AppIntents
import SwiftUI
import WidgetKit

// "Clusters": every context, or the ones picked in Edit Widget. Medium = compact rows; Large = cards; Extra Large = full columns.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct SelectClustersIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Clusters"
    static var description = IntentDescription("Pick which kube contexts to show. Leave empty to show all of them.")

    @Parameter(title: "Clusters")
    var clusters: [ClusterEntity]?
}

struct ClustersProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: SelectClustersIntent, in context: Context) async -> SnapshotEntry {
        let snap = Stores.snapshot.load() ?? (context.isPreview ? .placeholder : .empty)
        return SnapshotEntry(date: .now, snapshot: filter(snap, configuration))
    }

    func timeline(for configuration: SelectClustersIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entry = SnapshotEntry(date: .now, snapshot: filter(Stores.snapshot.load() ?? .empty, configuration))
        // The host app pushes reloads when data changes; this is just a fallback.
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900)))
    }

    private func filter(_ snap: Snapshot, _ config: SelectClustersIntent) -> Snapshot {
        guard let picked = config.clusters, !picked.isEmpty else { return snap }
        let ids = Set(picked.map(\.id))
        var s = snap
        s.clusters = snap.clusters.filter { ids.contains($0.name) }
        return s
    }
}

struct ClustersWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Clusters", intent: SelectClustersIntent.self, provider: ClustersProvider()) { entry in
            ClustersView(entry: entry)
        }
        .configurationDisplayName("Clusters")
        .description("Health and usage for your kube contexts. Edit the widget to pick which ones. Click one to open k9s.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

private func rank(_ s: ClusterStatus) -> Int {
    switch s { case .degraded: 0; case .up: 1; case .down: 2 }
}

extension Snapshot {
    var sorted: [ClusterSnapshot] {
        clusters.sorted {
            (rank($0.status), $0.shortName.lowercased()) < (rank($1.status), $1.shortName.lowercased())
        }
    }
    var live: [ClusterSnapshot] { sorted.filter { $0.status != .down } }
    var down: [ClusterSnapshot] { sorted.filter { $0.status == .down } }

    func link(_ c: ClusterSnapshot) -> URL {
        c.needsSSO ? ssoURL(profile: c.awsProfile!) : k9sURL(for: c.name)
    }
}

struct ClustersView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if entry.snapshot.clusters.isEmpty {
                VStack {
                    ClustersHeader(snapshot: entry.snapshot)
                    Spacer()
                    Text(entry.snapshot.updated == .distantPast
                         ? "Launch KubeWidget.app to start polling" : "No contexts")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                switch family {
                case .systemLarge: ClustersLarge(snapshot: entry.snapshot)
                case .systemExtraLarge: ClustersXL(snapshot: entry.snapshot)
                default: ClustersMedium(snapshot: entry.snapshot)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ClustersHeader: View {
    let snapshot: Snapshot

    var body: some View {
        let stale = snapshot.updated != .distantPast && Date().timeIntervalSince(snapshot.updated) > 600
        HStack(spacing: 5) {
            Image(systemName: "helm").font(.system(size: 11, weight: .bold))
            Text("Clusters").font(.system(size: 12, weight: .bold))
            Text("\(snapshot.live.count)/\(snapshot.clusters.count) up")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if snapshot.updated != .distantPast {
                Text(snapshot.updated, style: .relative)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70, alignment: .trailing)
            }
        }
    }
}

struct ClustersMedium: View {
    let snapshot: Snapshot
    var maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ClustersHeader(snapshot: snapshot)
            ForEach(snapshot.sorted.prefix(maxRows)) { c in
                TapLink(url: snapshot.link(c)) {
                    ClusterRow(cluster: c, signingIn: snapshot.signingIn(c))
                }
            }
            if snapshot.clusters.count > maxRows {
                Text("+\(snapshot.clusters.count - maxRows) more").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ClustersLarge: View {
    let snapshot: Snapshot

    var body: some View {
        // Cards are tall; with many contexts, trade them for rows until everything fits.
        ViewThatFits(in: .vertical) {
            ForEach(Self.fallbacks, id: \.self) { f in
                layout(cards: f.cards, maxRows: f.maxRows)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private struct Fallback: Hashable { let cards: Int; let maxRows: Int? }

    /// Tried in order until one fits: 3…0 cards with every other context as a row, then fewer rows.
    private static let fallbacks: [Fallback] =
        (0...3).reversed().map { Fallback(cards: $0, maxRows: nil) }
        + (1...12).reversed().map { Fallback(cards: 0, maxRows: $0) }

    /// Clusters with metrics make the most useful cards.
    private var cardOrder: [ClusterSnapshot] {
        let live = snapshot.live
        return live.filter { $0.cpuFrac != nil } + live.filter { $0.cpuFrac == nil }
    }

    private func layout(cards: Int, maxRows: Int?) -> some View {
        let order = cardOrder
        let carded = Array(order.prefix(cards))
        let rest = snapshot.sorted.filter { c in !carded.contains { $0.id == c.id } }
        let rows = maxRows.map { rest.count > $0 ? Array(rest.prefix($0 - 1)) : rest } ?? rest
        return VStack(alignment: .leading, spacing: 6) {
            ClustersHeader(snapshot: snapshot)
            ForEach(carded) { c in
                TapLink(url: snapshot.link(c)) {
                    ClusterCard(cluster: c, signingIn: snapshot.signingIn(c), dense: cards >= 3 || !rest.isEmpty)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(rows) { c in
                    TapLink(url: snapshot.link(c)) {
                        ClusterRow(cluster: c, signingIn: snapshot.signingIn(c))
                            .padding(.horizontal, carded.isEmpty ? 0 : 8)
                    }
                }
                if rows.count < rest.count {
                    Text("+\(rest.count - rows.count) more").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ClustersXL: View {
    let snapshot: Snapshot

    var body: some View {
        let live = snapshot.live.filter { $0.cpuFrac != nil } + snapshot.live.filter { $0.cpuFrac == nil }
        let rest = Array(live.dropFirst(3)) + snapshot.down
        VStack(alignment: .leading, spacing: 6) {
            ClustersHeader(snapshot: snapshot)
            HStack(alignment: .top, spacing: 10) {
                ForEach(live.prefix(3)) { c in
                    TapLink(url: snapshot.link(c)) {
                        ClusterDetail(cluster: c, signingIn: snapshot.signingIn(c),
                                      maxNodes: 9, maxIssues: 2, sparkHeight: 16)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
                    }
                }
            }
            if !rest.isEmpty {
                // As many chips as fit on one line, then "+N more".
                ViewThatFits(in: .horizontal) {
                    ForEach((0...rest.count).reversed(), id: \.self) { n in
                        HStack(spacing: 14) {
                            ForEach(rest.prefix(n)) { c in
                                TapLink(url: snapshot.link(c)) { DownChip(cluster: c, signingIn: snapshot.signingIn(c)) }
                            }
                            if n < rest.count {
                                Text("+\(rest.count - n) more").font(.system(size: 9)).foregroundStyle(.tertiary)
                            }
                        }
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct DownChip: View {
    let cluster: ClusterSnapshot
    var signingIn = false

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: cluster.status)
            Text(cluster.shortName).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            Text(cluster.reason ?? cluster.status.rawValue)
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            if cluster.needsSSO { SSOBadge(signingIn: signingIn, compact: true) }
        }
    }
}

/// One-line row (medium widget, and down clusters elsewhere).
struct ClusterRow: View {
    let cluster: ClusterSnapshot
    var signingIn = false

    var body: some View {
        let c = cluster
        HStack(spacing: 7) {
            StatusDot(status: c.status)
            Text(c.shortName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if c.status == .down {
                Text(c.reason ?? "down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("\(c.nodesReady)/\(c.nodesTotal)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(c.nodesReady < c.nodesTotal ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize()
                VStack(spacing: 2) {
                    MiniBar(label: "CPU", frac: c.cpuFrac)
                    MiniBar(label: "MEM", frac: c.memFrac)
                }
                .frame(width: 96)
            }
            if c.needsSSO {
                SSOBadge(signingIn: signingIn, compact: true)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
