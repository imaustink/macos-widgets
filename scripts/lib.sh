# Shared helpers for the build/install scripts. Sourced, not executed.

set -euo pipefail
ROOT="$(cd "$(dirname "${(%):-%x}")/.." && pwd)"
cd "$ROOT"

APP_NAME=KubeWidget
EXT_NAME=KubeWidgetExtension
DERIVED="$ROOT/build/dd"
BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ -t 1 ]]; then
  bold=$'\e[1m' red=$'\e[31m' yellow=$'\e[33m' green=$'\e[32m' dim=$'\e[2m' reset=$'\e[0m'
else
  bold='' red='' yellow='' green='' dim='' reset=''
fi
step() { print -r -- "${bold}==>${reset} $*"; }
ok()   { print -r -- "${green}✓${reset} $*"; }
warn() { print -r -- "${yellow}!${reset} $*" >&2; }
die()  { print -r -- "${red}✗${reset} $*" >&2; exit 1; }

# Xcode (not just the Command Line Tools) is needed for WidgetKit and the SwiftUI macros.
use_xcode() {
  if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    local selected; selected="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$selected" == *.app/Contents/Developer ]]; then
      export DEVELOPER_DIR="$selected"
    else
      local xcode; xcode="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1 || true)"
      [[ -n "$xcode" ]] || die "Xcode is required (the Command Line Tools alone can't build widgets). Install it from the App Store."
      export DEVELOPER_DIR="$xcode/Contents/Developer"
    fi
  fi
  [[ -d "$DEVELOPER_DIR" ]] || die "DEVELOPER_DIR=$DEVELOPER_DIR doesn't exist."
}

require_xcodegen() {
  command -v xcodegen >/dev/null || die "xcodegen is required: ${bold}brew install xcodegen${reset}"
}

# The Team ID from your "Apple Development" signing certificate. A free Apple ID works:
# Xcode → Settings → Accounts → add your Apple ID → Manage Certificates → + → Apple Development.
detect_team() {
  if [[ -n "${TEAM:-}" ]]; then print -r -- "$TEAM"; return; fi
  local hashes; hashes=($(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Apple Development:/ { print $2 }'))
  (( ${#hashes} )) || die "No Apple Development signing certificate found.
  Widgets must be signed. A free Apple ID is enough:
    Xcode → Settings → Accounts → add your Apple ID → Manage Certificates → + → Apple Development
  Then run this again. (Or pass TEAM=XXXXXXXXXX if you know your Team ID.)"
  local teams=() h subject team
  for h in $hashes; do
    subject="$(security find-certificate -a -Z -p -c "Apple Development" 2>/dev/null \
      | awk -v h="$h" '/^SHA-1 hash:/ { keep = ($3 == h) } keep && /BEGIN/,/END/' \
      | openssl x509 -noout -subject 2>/dev/null || true)"
    team="$(print -r -- "$subject" | grep -oE 'OU ?= ?[A-Z0-9]{10}' | grep -oE '[A-Z0-9]{10}$' || true)"
    [[ -n "$team" && ${teams[(Ie)$team]} -eq 0 ]] && teams+=("$team")
  done
  (( ${#teams} )) || die "Couldn't read the Team ID from your certificate. Pass it explicitly: TEAM=XXXXXXXXXX"
  (( ${#teams} == 1 )) || die "You have certificates for several teams (${teams[*]}). Pick one: TEAM=XXXXXXXXXX make install"
  print -r -- "${teams[1]}"
}

# Quit an installed copy and its widget extension (which otherwise keeps serving old code).
# Matches by path so other copies, e.g. a fork with another bundle ID, are left alone.
stop_app() {
  local app="$1" id; id="$(plist_get "$app" CFBundleIdentifier)"
  [[ -n "$id" ]] && osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 || true
  pkill -f "$app/Contents/" 2>/dev/null || true
}

# Read a key from an installed app's Info.plist.
plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }
