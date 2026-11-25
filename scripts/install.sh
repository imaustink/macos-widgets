#!/bin/zsh
# Builds and installs KubeWidget into ~/Applications (override with INSTALL_DIR), then launches it.
source "${0:A:h}/lib.sh"

[[ "${1:-}" == "--no-build" ]] || "$ROOT/scripts/build.sh"
[[ -d "$BUILT_APP" ]] || die "Nothing built yet. Run make build."

command -v kubectl >/dev/null || warn "kubectl not found on PATH. The cluster widgets need it."
command -v k9s >/dev/null || warn "k9s not found. Clicks will open a plain kubectl shell instead (brew install k9s for the full experience)."

dest="$INSTALL_DIR/$APP_NAME.app"
step "Installing to $dest"
[[ -d "$dest" ]] && stop_app "$dest"

mkdir -p "$INSTALL_DIR"
rm -rf "$dest"
ditto "$BUILT_APP" "$dest"
"$LSREGISTER" -f -R "$dest"
pluginkit -a "$dest/Contents/PlugIns/$EXT_NAME.appex" 2>/dev/null || true
# Re-index the App Intents that configure each widget. linkd can drop a bundle
# when another copy with the same ID is unregistered (as build.sh does), and
# widgets then fail with "Returned view collection was either nil or empty".
killall linkd 2>/dev/null || true
# Nudge the widget host so the gallery picks up the new build.
killall chronod 2>/dev/null || true

open "$dest"
ok "Installed and launched. Look for the helm icon in the menu bar."
cat <<MSG

Next:
  • Right-click the desktop → Edit Widgets… → search "KubeWidget".
  • If macOS asks, allow Local Network access (needed for clusters/hosts on your LAN).
  • Menu bar icon → Open at Login, to keep it running.
MSG
