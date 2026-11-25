# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

- App icon, so KubeWidget is no longer blank in the widget gallery.
- Clicking a cluster or namespace without k9s installed opens a terminal switched to that context (`kubectl config use-context`) instead of failing.

## 1.0.0

First public release.

- **Clusters** widget (medium, large, extra large): every kube context, or the ones you pick, with status, CPU/memory history, nodes, pods, workloads and failing pods. Adapts its layout to the number of contexts.
- **Cluster** widget (small, medium, large): one context in detail.
- **Namespace** widget (small, medium, large): usage against requests and limits, workloads and pods for one namespace.
- **SSH** widget (small to extra large): hosts from `~/.ssh/config` with reachability, with a configurable host list and title.
- Click to open k9s (on a context or a namespace's pods) or SSH in, in Terminal, iTerm2, Ghostty, Warp, WezTerm or kitty.
- AWS SSO sign-in for expired EKS contexts.
- Menu bar app with the same information, per-context polling toggles and Open at Login.
- `make install` / `make uninstall` with automatic signing-team detection.
