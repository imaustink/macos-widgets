import Foundation

// kubewidget:// URLs. Widgets can't run code on click, so each row links to one of these
// and the host app (which registers the scheme) does the work.

private func link(_ action: String, _ query: [String: String]) -> URL {
    var c = URLComponents()
    c.scheme = "kubewidget"
    c.host = action
    c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return c.url!
}

/// Open k9s on a context, optionally scoped to a namespace's pods.
func k9sURL(for context: String, namespace: String? = nil) -> URL {
    var q = ["context": context]
    q["namespace"] = namespace
    return link("k9s", q)
}

/// Run `aws sso login` for a profile.
func ssoURL(profile: String) -> URL { link("sso", ["profile": profile]) }

/// Open a terminal running `ssh <alias>`.
func sshURL(for alias: String) -> URL { link("ssh", ["host": alias]) }
