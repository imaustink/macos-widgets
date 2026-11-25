import AppKit
import ServiceManagement
import SwiftUI

@main
struct KubeWidgetApp: App {
    init() {
        // Used by `make uninstall` so the login item doesn't outlive the app.
        if CommandLine.arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("KubeWidget", systemImage: "helm") {
            MenuContent(poller: delegate.poller, ssh: delegate.ssh)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let poller = Poller()
    let ssh = SSHMonitor()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Widgets can't run code; their rows link to kubewidget:// URLs, which land here.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await loadLoginShellEnvironment()
            poller.start()
            ssh.start()
        }
    }

    /// kubewidget:// links can be opened by any app or web page, not just our widgets. So only act on
    /// contexts, namespaces, hosts and profiles we already know about: never pass arbitrary strings
    /// to k9s, ssh or aws, where something like `-oProxyCommand=…` would be read as an option.
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let comps = URLComponents(string: s) else { return }
        func param(_ name: String) -> String? { comps.queryItems?.first { $0.name == name }?.value }
        switch comps.host {
        case "k9s":
            guard let ctx = param("context"), poller.allContexts.contains(ctx) else { return }
            let ns = param("namespace")
            if let ns, !(Stores.namespaces.load()?.namespaces.contains { $0.context == ctx && $0.name == ns } ?? false) {
                return
            }
            launchK9s(ctx, namespace: ns)
        case "sso":
            guard let p = param("profile"), poller.clusters.contains(where: { $0.awsProfile == p }) else { return }
            Task { await poller.ssoLogin(profile: p) }
        case "ssh":
            guard let h = param("host"), ssh.hosts.contains(where: { $0.alias == h }) else { return }
            launchSSH(h)
        case "refresh":
            Task { await poller.refresh(force: true) }
            Task { await ssh.refresh(force: true) }
        default: break
        }
    }
}
