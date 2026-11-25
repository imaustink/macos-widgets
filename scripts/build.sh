#!/bin/zsh
# Builds KubeWidget.app (menu bar app + embedded widget extension) into build/.
#   TEAM=XXXXXXXXXX       signing team (default: detected from your Apple Development certificate)
#   BUNDLE_ID_PREFIX=...  bundle ID prefix (default: com.austinkurpuis, from project.yml)
#   SIGN=0                build unsigned (CI only; an unsigned widget won't load)
source "${0:A:h}/lib.sh"

use_xcode
require_xcodegen

settings=(
  # A fresh build number every build. macOS caches each widget extension's list of widgets per
  # build number, so without this new or changed widgets never show up in the gallery.
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M%S)"
)
[[ -n "${BUNDLE_ID_PREFIX:-}" ]] && settings+=(BUNDLE_ID_PREFIX="$BUNDLE_ID_PREFIX")
if [[ "${SIGN:-1}" == 0 ]]; then
  settings+=(CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=UNSIGNED00)
else
  team="$(detect_team)"
  settings+=(DEVELOPMENT_TEAM="$team")
  step "Signing with team $team"
fi

step "Generating Xcode project"
xcodegen generate --quiet

step "Building (Release)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -quiet build "${settings[@]}" \
  2> >(grep -v -e 'IDERunDestination' -e '^--- xcodebuild: WARNING' -e '^{ platform' >&2)

# Keep the build copy from registering as a second widget provider next to the installed one.
"$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true
# Unregistering can make linkd drop the App Intents of the installed copy too (same bundle ID),
# leaving its widgets as grey placeholders. Restarting linkd makes it re-index.
killall linkd 2>/dev/null || true
ok "Built $BUILT_APP"
