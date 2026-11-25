import AppKit

// Opens commands (k9s, ssh) in the user's terminal of choice.

struct TerminalApp: Identifiable, Hashable {
    let name: String
    let bundleID: String
    var id: String { bundleID }

    static let all = [
        TerminalApp(name: "Terminal", bundleID: "com.apple.Terminal"),
        TerminalApp(name: "iTerm2", bundleID: "com.googlecode.iterm2"),
        TerminalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        TerminalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        TerminalApp(name: "WezTerm", bundleID: "com.github.wez.wezterm"),
        TerminalApp(name: "kitty", bundleID: "net.kovidgoyal.kitty"),
    ]

    static var installed: [TerminalApp] {
        all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// Chosen in the menu bar's Terminal picker. Stored as a bundle ID.
    static var current: TerminalApp {
        get {
            let id = UserDefaults.standard.string(forKey: "terminal") ?? ""
            // Older builds stored a name ("ghostty") rather than a bundle ID.
            return installed.first { $0.bundleID == id || $0.name.lowercased() == id.lowercased() } ?? all[0]
        }
        set { UserDefaults.standard.set(newValue.bundleID, forKey: "terminal") }
    }
}

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Opens k9s on a context (and optionally a namespace's pods). Without k9s installed, switches
/// kubectl to that context instead and leaves the user in a shell there.
func launchK9s(_ context: String, namespace: String? = nil) {
    launchInTerminal(name: "k9s-\(context)\(namespace.map { "-" + $0 } ?? "")",
                     title: "\(shortContextName(context))\(namespace.map { "/" + $0 } ?? "")",
                     script: k9sScript(context: context, namespace: namespace))
}

func k9sScript(context: String, namespace: String?) -> String {
    let ctx = shellQuote(context)
    let nsArgs = namespace.map { " --namespace=\(shellQuote($0)) --command=pods" } ?? ""
    let nsHint = namespace.map { " -n \($0)" } ?? ""
    return """
    if command -v k9s >/dev/null 2>&1; then
      exec k9s --context=\(ctx)\(nsArgs)
    fi
    kubectl config use-context \(ctx) || exit 1
    \(namespace.map { "kubectl get pods --namespace=\(shellQuote($0))" } ?? "kubectl get nodes")
    printf '\\n\\e[2mk9s isn'"'"'t installed (brew install k9s), so kubectl is now on this context.%s\\e[0m\\n\\n' \(shellQuote(nsHint.isEmpty ? "" : " Add\(nsHint) for this namespace."))
    exec "${SHELL:-/bin/zsh}" -l
    """
}

func launchSSH(_ alias: String) {
    launchInTerminal(name: "ssh-\(alias)", title: "ssh · \(alias)", script: "exec ssh -- \(shellQuote(alias))")
}

/// Writes an executable .command script to ~/Library/Caches/KubeWidget and opens it with the
/// chosen terminal. Using a login shell (`zsh -l`) picks up the user's PATH, AWS env, etc.
func launchInTerminal(name: String, title: String, script body: String) {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KubeWidget", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let safe = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    let file = dir.appendingPathComponent("\(safe).command")
    let script = """
    #!/bin/zsh -l
    printf '\\e]0;%s\\a' \(shellQuote(title))
    \(body)
    """
    do {
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    } catch {
        NSLog("KubeWidget: couldn't write \(file.path): \(error)")
        return
    }

    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = true
    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.current.bundleID) {
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: cfg)
    } else {
        NSWorkspace.shared.open(file)
    }
}
