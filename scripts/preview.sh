#!/bin/zsh
# Renders every widget layout to PNGs without installing anything.
#   scripts/preview.sh <out-dir>          demo data (used for the README screenshots)
#   scripts/preview.sh <out-dir> --live   your real kube contexts and ~/.ssh/config
source "${0:A:h}/lib.sh"
use_xcode

bin="$ROOT/build/kw-preview"
mkdir -p "$ROOT/build"
sources=(tools/preview/*.swift Shared/*.swift
         App/Shell.swift App/KubeProbe.swift App/SSHMonitor.swift
         ${(@)$(print -l Widget/*.swift | grep -v KubeWidgetBundle.swift)})
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0" -o "$bin" $sources
"$bin" "$@"
