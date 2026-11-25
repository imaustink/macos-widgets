import SwiftUI
import WidgetKit

func statusColor(_ s: ClusterStatus) -> Color {
    switch s {
    case .up: .green
    case .degraded: .orange
    case .down: .red
    }
}

func usageColor(_ frac: Double?) -> Color {
    guard let f = frac else { return .gray }
    return f > 0.85 ? .red : f > 0.65 ? .orange : .green
}

func pct(_ frac: Double?) -> String {
    frac.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
}

struct StatusDot: View {
    let status: ClusterStatus
    var size: CGFloat = 7

    var body: some View {
        Circle().fill(statusColor(status))
            .frame(width: size, height: size)
            .widgetAccentable()
    }
}

/// Thin horizontal usage bar with label and percentage.
struct MiniBar: View {
    let label: String
    let frac: Double?
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if let f = frac {
                        Capsule().fill(usageColor(f))
                            .frame(width: max(3, g.size.width * min(1, f)))
                    }
                }
            }
            .frame(height: 4)
            Text(detail ?? pct(frac))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Circular usage gauge.
struct Ring: View {
    let label: String
    let frac: Double?
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            if let f = frac {
                Circle()
                    .trim(from: 0, to: min(1, max(0.01, f)))
                    .stroke(usageColor(f), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(pct(frac)).font(.system(size: 13, weight: .bold, design: .rounded))
                Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

struct K9sBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "terminal.fill")
            Text("k9s")
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.quaternary))
    }
}

struct SSOBadge: View {
    var signingIn = false
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: signingIn ? "hourglass" : "key.fill")
            Text(signingIn ? "Signing in…" : (compact ? "Sign in" : "AWS SSO sign in"))
        }
        .font(.system(size: compact ? 9 : 10, weight: .semibold))
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(Capsule().fill(signingIn ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.orange.opacity(0.35))))
        .widgetAccentable()
    }
}

// MARK: - Rich detail components

func fmtCount(_ n: Int) -> String {
    n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
}

/// Area sparkline. Auto-scales so small usage still shows its shape; the % label carries the absolute.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var absolute = false  // values are raw (cores/bytes), not 0…1 fractions
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { g in
            let pts = points(in: g.size)
            if pts.count >= 2 {
                ZStack {
                    // In the monochrome/tinted desktop style a translucent fill renders as a solid slab.
                    if renderingMode == .fullColor {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.14))
                    }
                    Path { p in p.addLines(pts) }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: g.size.height - 0.5))
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height - 0.5))
                }
                .stroke(.quaternary, lineWidth: 1)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let n = values.count
        guard n >= 2 else { return [] }
        let peak = values.max() ?? 0
        let top = absolute ? max(peak * 1.25, 1e-9) : min(1, max(0.25, peak * 1.25))
        // Stretch whatever history exists across the full width.
        let step = size.width / CGFloat(n - 1)
        let start: CGFloat = 0
        return values.enumerated().map { i, v in
            CGPoint(x: start + step * CGFloat(i),
                    y: size.height * (1 - CGFloat(min(1, max(0, v / top)))) + 0.7)
        }
    }
}

struct UsageSpark: View {
    let label: String
    let frac: Double?
    let history: [Double]
    var detail: String? = nil
    var height: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(pct(frac))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(usageColor(frac))
                Spacer(minLength: 0)
                if let d = detail {
                    Text(d).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Sparkline(values: history, color: usageColor(frac)).frame(height: height)
        }
    }
}

private struct VBar: View {
    let frac: Double?

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Capsule().fill(usageColor(frac))
                    .frame(height: max(2, g.size.height * min(1, frac ?? 0)))
            }
        }
        .frame(width: 3)
    }
}

/// One cell per node: CPU and memory as two tiny vertical bars. Red cell = NotReady.
struct NodeStrip: View {
    let nodes: [NodeSnapshot]
    var height: CGFloat = 16
    var maxNodes = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(nodes.prefix(maxNodes)) { n in
                HStack(alignment: .bottom, spacing: 1) {
                    VBar(frac: n.cpuFrac)
                    VBar(frac: n.memFrac)
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(n.ready ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.red.opacity(0.5))))
            }
            if nodes.count > maxNodes {
                Text("+\(nodes.count - maxNodes)").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height)
    }
}

struct NodeRow: View {
    let node: NodeSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(node.ready ? (node.controlPlane ? Color.blue : Color.green) : Color.red)
                .frame(width: 5, height: 5)
            // ip-10-0-1-23.ec2.internal -> ip-10-0-1-23
            Text(node.name.split(separator: ".").first.map(String.init) ?? node.name)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84, alignment: .leading)
            MiniBar(label: "CPU", frac: node.cpuFrac)
            MiniBar(label: "MEM", frac: node.memFrac)
        }
    }
}

struct IssueRow: View {
    let issue: PodIssue

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 7))
                .foregroundStyle(issue.reason == "NotReady" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            Text("\(issue.namespace)/\(issue.name)")
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            Text(issue.reason)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(issue.reason == "NotReady" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .lineLimit(1)
                .fixedSize()
            if issue.restarts > 0 {
                Text("↻\(fmtCount(issue.restarts))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
    }
}

struct StatsLine: View {
    let cluster: ClusterSnapshot

    var body: some View {
        let c = cluster
        HStack(spacing: 8) {
            stat("\(c.podsRunning)", "pods")
            if c.podsBad > 0 { stat("\(c.podsBad)", "unhealthy", warn: true) }
            if let t = c.workloadsTotal, t > 0 {
                let r = c.workloadsReady ?? 0
                stat("\(r)/\(t)", "workloads", warn: r < t)
            }
            if let r = c.restarts, r > 0 { stat(fmtCount(r), "restarts") }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func stat(_ value: String, _ label: String, warn: Bool = false) -> some View {
        (Text(value).font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(warn ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            + Text(" " + label).font(.system(size: 8)).foregroundStyle(.secondary))
            .fixedSize()
    }
}

struct ClusterHeader: View {
    let cluster: ClusterSnapshot
    var signingIn = false
    var big = false

    var body: some View {
        let c = cluster
        HStack(spacing: 6) {
            StatusDot(status: c.status, size: big ? 8 : 7)
            Text(c.shortName)
                .font(.system(size: big ? 13 : 12, weight: .bold))
                .lineLimit(1)
                .layoutPriority(1)  // truncate the version label before the name
            if let v = c.versionLabel ?? c.subtitle {
                Text(v).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if c.status != .down {
                Text("\(c.nodesReady)/\(c.nodesTotal) nodes")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(c.nodesReady < c.nodesTotal ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize()
            }
            if c.needsSSO {
                SSOBadge(signingIn: signingIn, compact: true)
            } else {
                Image(systemName: "terminal").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Compact card used in the large "Clusters" widget.
struct ClusterCard: View {
    let cluster: ClusterSnapshot
    var signingIn = false
    var dense = false

    var body: some View {
        let c = cluster
        VStack(alignment: .leading, spacing: dense ? 4 : 5) {
            ClusterHeader(cluster: c, signingIn: signingIn)
            HStack(spacing: 12) {
                UsageSpark(label: "CPU", frac: c.cpuFrac, history: c.cpuHistory ?? [], height: dense ? 12 : 24)
                UsageSpark(label: "MEM", frac: c.memFrac, history: c.memHistory ?? [], height: dense ? 12 : 24)
            }
            if let nodes = c.nodes, nodes.count > 1 {
                NodeStrip(nodes: nodes, height: dense ? 11 : 18)
            }
            StatsLine(cluster: c)
            if !dense, let issue = c.issues?.first {
                IssueRow(issue: issue)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
    }
}

/// Full detail: XL columns and the large single-cluster widget.
struct ClusterDetail: View {
    let cluster: ClusterSnapshot
    var signingIn = false
    var maxNodes = 9
    var maxIssues = 3
    var sparkHeight: CGFloat = 24

    var body: some View {
        let c = cluster
        VStack(alignment: .leading, spacing: 6) {
            ClusterHeader(cluster: c, signingIn: signingIn, big: true)
            if c.status == .down {
                Spacer()
                Text(c.reason ?? "down").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                if c.needsSSO { SSOBadge(signingIn: signingIn).frame(maxWidth: .infinity) }
                Spacer()
            } else {
                UsageSpark(label: "CPU", frac: c.cpuFrac, history: c.cpuHistory ?? [],
                           detail: c.cpuUsed.map { "\(fmtCores($0))/\(fmtCores(c.cpuAlloc)) cores" }, height: sparkHeight)
                UsageSpark(label: "MEM", frac: c.memFrac, history: c.memHistory ?? [],
                           detail: c.memUsed.map { "\(fmtBytes($0))/\(fmtBytes(c.memAlloc))" }, height: sparkHeight)
                StatsLine(cluster: c)
                if let nodes = c.nodes, !nodes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(nodes.prefix(maxNodes)) { NodeRow(node: $0) }
                        if nodes.count > maxNodes {
                            Text("+\(nodes.count - maxNodes) more nodes").font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                    }
                }
                if let issues = c.issues, !issues.isEmpty, maxIssues > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(issues.prefix(maxIssues)) { IssueRow(issue: $0) }
                        if c.podsBad > maxIssues {
                            Text("+\(c.podsBad - maxIssues) more unhealthy pods")
                                .font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Links

private struct StaticPreviewKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Set by the offline PNG preview renderer, which can't draw `Link`.
    var staticPreview: Bool {
        get { self[StaticPreviewKey.self] }
        set { self[StaticPreviewKey.self] = newValue }
    }
}

struct TapLink<Content: View>: View {
    let url: URL
    @ViewBuilder let content: Content
    @Environment(\.staticPreview) private var preview

    var body: some View {
        if preview { content } else { Link(destination: url) { content } }
    }
}
