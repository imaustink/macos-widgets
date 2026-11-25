// Renders every widget layout to PNGs without installing anything. Used for README screenshots and
// for checking layouts quickly while developing. See CONTRIBUTING.md.
//
//   make screenshots            demo data   -> docs/images/
//   make preview                your real kube contexts and ~/.ssh/config -> build/preview/
//
// Direct use: kw-preview <out-dir> [--live]

import AppKit
import SwiftUI
import WidgetKit

@MainActor
func render<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat, _ path: String) {
    let view = v.frame(width: w, height: h).padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.16)))
        .environment(\.colorScheme, .dark)
        .environment(\.staticPreview, true)  // ImageRenderer can't draw Link; TapLink falls back to plain content
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("failed to render \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

/// Content sizes (inside the 16pt margin) that match how the widgets lay out on a macOS desktop.
enum Size {
    static let small = (CGFloat(140), CGFloat(140))
    static let medium = (CGFloat(330), CGFloat(140))
    static let large = (CGFloat(330), CGFloat(340))
    static let xl = (CGFloat(700), CGFloat(340))
}

@MainActor
func renderAll(snapshot: Snapshot, namespace: NamespaceSnapshot?, ssh: SSHFile, to out: String) {
    func r<V: View>(_ v: V, _ s: (CGFloat, CGFloat), _ name: String) { render(v, s.0, s.1, "\(out)/\(name).png") }
    r(ClustersMedium(snapshot: snapshot), Size.medium, "clusters-medium")
    r(ClustersLarge(snapshot: snapshot), Size.large, "clusters-large")
    r(ClustersXL(snapshot: snapshot), Size.xl, "clusters-xl")
    if let c = snapshot.live.first {
        r(ClusterDetail(cluster: c, maxNodes: 12, maxIssues: 4, sparkHeight: 20), Size.large, "cluster-large")
    }
    if let ns = namespace {
        r(NamespaceSmall(ns: ns), Size.small, "namespace-small")
        r(NamespaceMedium(ns: ns), Size.medium, "namespace-medium")
        r(NamespaceLarge(ns: ns), Size.large, "namespace-large")
    }
    let entry = SSHEntry(date: .now, file: ssh)
    for (family, size, name) in [(WidgetFamily.systemSmall, Size.small, "small"), (.systemMedium, Size.medium, "medium"),
                                 (.systemLarge, Size.large, "large"), (.systemExtraLarge, Size.xl, "xl")] {
        r(SSHGrid(entry: entry, family: family), size, "ssh-\(name)")
    }
}

@MainActor
func live() async -> (Snapshot, NamespaceSnapshot?, SSHFile) {
    await loadLoginShellEnvironment()
    let names = await sh("kubectl", ["config", "get-contexts", "-o", "name"]).out
        .split(separator: "\n").map(String.init)
    let profiles = await awsProfilesByContext()
    var clusters: [ClusterSnapshot] = []
    var namespaces: [NamespaceSnapshot] = []
    for n in names {
        let r = await probe(n)
        namespaces += r.namespaces
        var c = r.cluster
        c.awsProfile = profiles[n]
        c.cpuHistory = walk(c.cpuFrac)
        c.memHistory = walk(c.memFrac)
        clusters.append(c)
    }
    // NS=<name> picks the namespace to render; default is the busiest one.
    let want = ProcessInfo.processInfo.environment["NS"]
    var ns = namespaces.first { $0.name == want } ?? namespaces.max { ($0.cpuUsed ?? 0) < ($1.cpuUsed ?? 0) }
    if var n = ns {
        n.cpuHistory = absWalk(n.cpuUsed)
        n.memHistory = absWalk(n.memUsed)
        ns = n
    }
    let ssh = SSHMonitor()
    await ssh.refresh()
    return (Snapshot(updated: .now.addingTimeInterval(-25), clusters: clusters), ns,
            SSHFile(updated: .now.addingTimeInterval(-20), hosts: ssh.hosts))
}

let args = CommandLine.arguments.dropFirst()
guard let out = args.first(where: { !$0.hasPrefix("--") }) else {
    print("usage: kw-preview <out-dir> [--live]")
    exit(2)
}
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

Task { @MainActor in
    if args.contains("--live") {
        let (snap, ns, ssh) = await live()
        renderAll(snapshot: snap, namespace: ns, ssh: ssh, to: out)
    } else {
        renderAll(snapshot: Demo.snapshot, namespace: Demo.namespace, ssh: Demo.ssh, to: out)
    }
    print("rendered to \(out)")
    exit(0)
}
RunLoop.main.run()
