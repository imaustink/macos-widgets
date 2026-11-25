# Security

## What KubeWidget does on your machine

- The menu bar app runs `kubectl`, `aws sso login` and `ssh -G` as you, with your login shell's `PATH` and `KUBECONFIG`. The `kubectl` calls are read-only: `get`, `top` and `config view`.
- It opens plain TCP connections to the SSH port of hosts in `~/.ssh/config` to check reachability. It never logs in or sends data.
- It stores cluster and host summaries (names, counts, usage, pod names) as JSON in its App Group container under `~/Library/Group Containers/`. Nothing is sent anywhere else.
- Clicking a widget opens a `kubewidget://` URL. Since any app or web page can open such a URL, the app only acts on contexts, namespaces, SSH aliases and AWS profiles it has already discovered on your machine. Anything else is ignored. Values are also shell-quoted, and passed so they can't be read as command-line options (`ssh -- <alias>`, `k9s --context=<name>`).

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's [private vulnerability reporting](https://github.com/imaustink/macos-widgets/security/advisories/new) instead. I'll reply as soon as I can.
