#!/bin/zsh
# Removes KubeWidget completely: login item, widgets, app, shared data, caches and preferences.
#   --keep-data   leave cached snapshots and preferences in place
source "${0:A:h}/lib.sh"

keep_data=0
[[ "${1:-}" == "--keep-data" ]] && keep_data=1

bundle_id="${BUNDLE_ID_PREFIX:-com.austinkurpuis}.kubewidget"
ext_id="$bundle_id.widget"
group_id=""

# Only copies with our bundle ID; a fork built with another BUNDLE_ID_PREFIX is left alone.
apps=()
for dir in "$INSTALL_DIR" "$HOME/Applications" /Applications; do
  app="$dir/$APP_NAME.app"
  [[ -d "$app" && "$(plist_get "$app" CFBundleIdentifier)" == "$bundle_id" ]] || continue
  (( ${apps[(Ie)$app]} )) || apps+=("$app")
done

if (( ${#apps} )); then
  group_id="$(plist_get "${apps[1]}" KWAppGroupID)"
  # Remove the Open at Login entry while the app still exists to do it.
  "${apps[1]}/Contents/MacOS/$APP_NAME" --unregister-login-item >/dev/null 2>&1 || true
else
  warn "No $APP_NAME.app with bundle ID $bundle_id in $INSTALL_DIR, ~/Applications or /Applications. Cleaning up leftovers only."
fi

for app in $apps; do
  step "Removing $app"
  stop_app "$app"
  pluginkit -r "$app/Contents/PlugIns/$EXT_NAME.appex" 2>/dev/null || true
  "$LSREGISTER" -u "$app" 2>/dev/null || true
  rm -rf "$app"
done
# The build copy, if any, shouldn't keep offering widgets either.
[[ -d "$BUILT_APP" ]] && "$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true

if (( ! keep_data )); then
  step "Removing data and preferences"
  paths=("$HOME/Library/Caches/KubeWidget")
  [[ -n "$bundle_id" ]] && paths+=("$HOME/Library/Caches/$bundle_id" "$HOME/Library/HTTPStorages/$bundle_id")
  [[ -n "$ext_id" ]] && paths+=("$HOME/Library/Containers/$ext_id")
  if [[ -n "$group_id" ]]; then
    paths+=("$HOME/Library/Group Containers/$group_id")
  else
    paths+=("$HOME/Library/Group Containers/"*.group."$bundle_id"(N))
  fi
  for p in $paths; do
    [[ -e "$p" ]] || continue
    if rm -rf "$p" 2>/dev/null; then
      print -r -- "  ${dim}removed $p${reset}"
    else
      # The widget's sandbox container is emptied, but macOS won't let Terminal delete the folder itself.
      print -r -- "  ${dim}emptied $p (macOS keeps the empty folder; delete it in Finder if you like)${reset}"
    fi
  done
  [[ -n "$bundle_id" ]] && defaults delete "$bundle_id" >/dev/null 2>&1 || true
fi

# Make the desktop drop the widgets now rather than at next login.
killall chronod 2>/dev/null || true
ok "KubeWidget uninstalled."
print -r -- "${dim}System Settings may still list KubeWidget under Privacy & Security → Local Network; it no longer does anything.${reset}"
