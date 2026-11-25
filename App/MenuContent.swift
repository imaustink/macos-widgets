import ServiceManagement
import SwiftUI

// The menu bar dropdown: every cluster and SSH host, plus settings.

struct MenuContent: View {
    @ObservedObject var poller: Poller
    @ObservedObject var ssh: SSHMonitor

    var body: some View {
        if poller.clusters.isEmpty {
            Text(poller.refreshing ? "Probing clusters…" : "No contexts")
        }
        ForEach(poller.clusters) { c in
            if c.needsSSO, let p = c.awsProfile {
                Button("🔑  \(c.shortName)  —  \(poller.ssoInProgress.contains(p) ? "signing in…" : "Sign in to AWS (\(p))")") {
                    Task { await poller.ssoLogin(profile: p) }
                }
                .disabled(poller.ssoInProgress.contains(p))
            } else {
                Button("\(dot(c.status))  \(c.shortName)  —  \(summary(c))") { launchK9s(c.name) }
            }
        }
        if poller.clusters.contains(where: \.needsSSO) {
            Divider()
            Button("Sign In to All Expired AWS SSO") { Task { await poller.ssoLoginAllExpired() } }
                .disabled(!poller.ssoInProgress.isEmpty)
        }
        if let err = poller.ssoError {
            Text("⚠️ SSO failed — \(err)")
        }
        Divider()
        if let t = poller.lastUpdated {
            Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
        }
        Button(poller.refreshing ? "Refreshing…" : "Refresh Now") {
            Task { await poller.refresh(force: true) }
            Task { await ssh.refresh(force: true) }
        }
        .keyboardShortcut("r")
        .disabled(poller.refreshing)
        if !ssh.hosts.isEmpty {
            Menu("SSH") {
                ForEach(ssh.hosts) { h in
                    Button("\(h.reachable.map { $0 ? "🟢" : "🔴" } ?? "⚪️")  \(h.alias)  —  \(h.target)") { launchSSH(h.alias) }
                }
            }
        }
        Menu("Contexts") {
            ForEach(poller.allContexts, id: \.self) { n in
                Toggle(shortContextName(n), isOn: Binding(
                    get: { !poller.hidden.contains(n) },
                    set: { _ in poller.toggleHidden(n) }))
            }
        }
        Picker("Terminal", selection: Binding(
            get: { TerminalApp.current },
            set: { TerminalApp.current = $0 })) {
            ForEach(TerminalApp.installed) { Text($0.name).tag($0) }
        }
        Toggle("Open at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            }))
        Divider()
        Button("Quit KubeWidget") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func dot(_ s: ClusterStatus) -> String {
        switch s { case .up: "🟢"; case .degraded: "🟠"; case .down: "🔴" }
    }

    private func summary(_ c: ClusterSnapshot) -> String {
        guard c.status != .down else { return c.reason ?? "down" }
        let cpu = c.cpuFrac.map { "CPU \(Int($0 * 100))%" } ?? "CPU –"
        let mem = c.memFrac.map { "MEM \(Int($0 * 100))%" } ?? "MEM –"
        return "\(c.nodesReady)/\(c.nodesTotal) nodes · \(cpu) · \(mem)"
    }
}
