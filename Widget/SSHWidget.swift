import AppIntents
import SwiftUI
import WidgetKit

// "SSH": hosts from ~/.ssh/config. Click one to open a terminal running `ssh <alias>`.

struct SSHHostEntity: AppEntity {
    let id: String  // alias

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "SSH Host"
    static var defaultQuery = SSHHostQuery()

    var displayRepresentation: DisplayRepresentation {
        let target = Stores.ssh.load()?.hosts.first { $0.alias == id }?.target
        return DisplayRepresentation(title: "\(id)", subtitle: target.map { "\($0)" })
    }
}

struct SSHHostQuery: EntityStringQuery {
    private func all() -> [SSHHostEntity] {
        (Stores.ssh.load()?.hosts ?? []).map { SSHHostEntity(id: $0.alias) }
    }
    func entities(for identifiers: [String]) async throws -> [SSHHostEntity] { identifiers.map(SSHHostEntity.init) }
    func entities(matching string: String) async throws -> [SSHHostEntity] {
        let q = string.lowercased()
        let hosts = Stores.ssh.load()?.hosts ?? []
        return hosts.filter { $0.alias.lowercased().contains(q) || $0.target.lowercased().contains(q) }
            .map { SSHHostEntity(id: $0.alias) }
    }
    func suggestedEntities() async throws -> [SSHHostEntity] { all() }
}

struct SelectSSHHostsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Hosts"
    static var description = IntentDescription("Pick which SSH hosts to show. Leave empty to show every host in ~/.ssh/config.")

    @Parameter(title: "Hosts")
    var hosts: [SSHHostEntity]?

    @Parameter(title: "Title", default: "SSH")
    var title: String?
}

struct SSHEntry: TimelineEntry {
    let date: Date
    let file: SSHFile
    var title = "SSH"
}

struct SSHProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SSHEntry { SSHEntry(date: .now, file: .placeholder) }

    func snapshot(for configuration: SelectSSHHostsIntent, in context: Context) async -> SSHEntry {
        let e = entry(for: configuration)
        return e.file.hosts.isEmpty && context.isPreview ? placeholder(in: context) : e
    }

    func timeline(for configuration: SelectSSHHostsIntent, in context: Context) async -> Timeline<SSHEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(900)))
    }

    private func entry(for config: SelectSSHHostsIntent) -> SSHEntry {
        var file = Stores.ssh.load() ?? .empty
        if let picked = config.hosts, !picked.isEmpty {
            // Keep the order the user picked them in.
            let byAlias = Dictionary(file.hosts.map { ($0.alias, $0) }, uniquingKeysWith: { a, _ in a })
            file.hosts = picked.compactMap { byAlias[$0.id] }
        }
        let t = config.title?.trimmingCharacters(in: .whitespaces)
        return SSHEntry(date: .now, file: file, title: (t?.isEmpty ?? true) ? "SSH" : t!)
    }
}

struct SSHWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SSH", intent: SelectSSHHostsIntent.self, provider: SSHProvider()) { entry in
            SSHWidgetView(entry: entry)
        }
        .configurationDisplayName("SSH")
        .description("Hosts from ~/.ssh/config with reachability. Click one to SSH in.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct SSHWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SSHEntry

    var body: some View {
        SSHGrid(entry: entry, family: family)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SSHGrid: View {
    let entry: SSHEntry
    let family: WidgetFamily

    /// Two-line rows (alias over user@host) when they all fit, otherwise denser one-line rows.
    private var layout: (columns: Int, rows: Int, showTarget: Bool) {
        let n = entry.file.hosts.count
        switch family {
        case .systemSmall: return (1, 6, false)
        case .systemMedium: return (3, 6, false)
        case .systemLarge: return n <= 20 ? (2, 10, true) : (3, 16, false)
        case .systemExtraLarge: return n <= 40 ? (4, 10, true) : (5, 16, false)
        default: return (1, 6, false)
        }
    }

    var body: some View {
        let hosts = entry.file.hosts
        let (cols, rows, showTarget) = layout
        let capacity = cols * rows
        // When everything won't fit, drop the last slot for a "+N more" line.
        let shown = hosts.count > capacity ? Array(hosts.prefix(capacity - 1)) : hosts
        let perCol = max(1, Int((Double(shown.count) / Double(cols)).rounded(.up)))

        VStack(alignment: .leading, spacing: 5) {
            SSHHeader(entry: entry, compact: family == .systemSmall)
            if hosts.isEmpty {
                Spacer()
                Text(entry.file.updated == .distantPast
                     ? "Launch KubeWidget.app to read ~/.ssh/config" : "No hosts in ~/.ssh/config")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: cols > 2 ? 10 : 12) {
                    ForEach(0..<cols, id: \.self) { c in
                        VStack(alignment: .leading, spacing: showTarget ? 6 : (family == .systemSmall ? 4 : 3)) {
                            ForEach(Array(shown.dropFirst(c * perCol).prefix(perCol))) { h in
                                TapLink(url: sshURL(for: h.alias)) {
                                    SSHRow(host: h, showTarget: showTarget)
                                }
                            }
                            if c == cols - 1, hosts.count > shown.count {
                                Text("+\(hosts.count - shown.count) more")
                                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct SSHHeader: View {
    let entry: SSHEntry
    var compact = false

    var body: some View {
        let hosts = entry.file.hosts
        let checked = hosts.filter { $0.reachable != nil }
        let up = checked.filter { $0.reachable == true }.count
        HStack(spacing: 5) {
            Image(systemName: "terminal").font(.system(size: 11, weight: .bold))
            Text(entry.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
            if !checked.isEmpty {
                Text("\(up)/\(checked.count) up")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            if !compact, entry.file.updated != .distantPast {
                Text(entry.file.updated, style: .relative)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70, alignment: .trailing)
            }
        }
    }
}

struct SSHRow: View {
    let host: SSHHost
    var showTarget = false

    var body: some View {
        let h = host
        HStack(alignment: showTarget ? .top : .center, spacing: 6) {
            Circle()
                .fill(h.reachable.map { $0 ? Color.green : Color.red } ?? Color.gray)
                .frame(width: 6, height: 6)
                .padding(.top, showTarget ? 4 : 0)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(h.alias)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    status
                }
                if showTarget {
                    Text(h.target)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var status: some View {
        Group {
            if let j = host.jump {
                Text("↪\(j)")
            } else if host.reachable == false {
                Text("down").foregroundStyle(.red)
            } else if let ms = host.latencyMs {
                Text(verbatim: "\(ms)ms")
            }
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
}
