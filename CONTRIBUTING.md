# Contributing to KubeWidget

Thanks for helping out! Bug reports, feature ideas and pull requests are all welcome. For anything bigger than a small fix, please open an issue first so we can agree on the approach.

## Getting set up

You need the same things as for [installing](README.md#requirements): macOS 14+, Xcode 16+, `brew install xcodegen`, and an Apple Development certificate (a free Apple ID works).

```sh
make help         # list targets
make install      # build, install to ~/Applications, launch
make preview      # render every widget with YOUR clusters and SSH hosts → build/preview/*.png
make screenshots  # render every widget with demo data → docs/images/*.png
make project      # generate KubeWidget.xcodeproj to work in Xcode
make uninstall    # remove everything
```

The Xcode project is generated from [`project.yml`](project.yml) by XcodeGen and isn't checked in. If you add, remove or rename files, run `make project` again. In Xcode, choose your team under **Signing & Capabilities** for both targets.

## Layout

```
App/         Menu bar app (not sandboxed). Polls kubectl and ssh, writes JSON, handles clicks.
  KubeWidgetApp.swift     entry point, kubewidget:// URL handling
  Poller.swift            per-minute cluster polling, history, widget reload throttling
  KubeProbe.swift         kubectl calls and parsing for one context
  SSHMonitor.swift        ~/.ssh/config parsing, `ssh -G`, TCP reachability
  Shell.swift             running CLI tools with the login shell's PATH/KUBECONFIG
  TerminalLauncher.swift  opening k9s/ssh in the chosen terminal
  MenuContent.swift       the menu bar dropdown
Widget/      WidgetKit extension (sandboxed). Reads JSON, draws, links back to the app.
  KubeWidgetBundle.swift  registers the widgets
  ClustersWidget.swift    "Clusters" (all/selected contexts)
  ClusterWidget.swift     "Cluster" (one context)
  NamespaceWidget.swift   "Namespace"
  SSHWidget.swift         "SSH"
  Components.swift        shared views: bars, rings, sparklines, rows, TapLink
Shared/      Compiled into both targets.
  AppGroup.swift          App Group ID and the JSON stores
  Clusters.swift, Namespaces.swift, SSH.swift   data models
  Links.swift             kubewidget:// URL builders
  Format.swift            number formatting
tools/preview/   Offline renderer used by `make preview` / `make screenshots`
tools/icon/      Draws the app icon (`make icon`)
scripts/         build, install, uninstall and preview scripts behind the Makefile
```

### How data flows

1. `Poller` (every 60s) lists contexts and runs `probe(context)` for each one in parallel. `SSHMonitor` does the same for SSH hosts.
2. Results are saved as `snapshot.json`, `namespaces.json` and `ssh.json` in the App Group container (`Stores.*`).
3. The app asks WidgetKit to reload. Each widget's timeline provider reads the JSON and renders it.
4. A click opens a `kubewidget://…` URL (see `Shared/Links.swift`). macOS hands it to the app, which launches k9s, ssh or `aws sso login`.

The widget extension never runs commands or touches the network. Keep it that way: anything that needs `kubectl` belongs in the app.

## Development loop

**Layouts:** `make preview` renders every widget, at every size, from your real data into `build/preview/`. It's the fastest way to check a layout change, since there's no install and no waiting on WidgetKit. Set `NS=<namespace>` to choose the namespace rendered. Use `make screenshots` to check with the demo data in `tools/preview/Demo.swift`.

**The real thing:** `make install`, then look at your desktop. Debug output from the app goes to the unified log:

```sh
log stream --predicate 'process == "KubeWidget" OR process == "KubeWidgetExtension"'
```

The JSON the widgets read is in `~/Library/Group Containers/<TEAM>.group.<prefix>.kubewidget/`.

## Things that will bite you

- **The widget gallery caches by build number.** `scripts/build.sh` stamps every build with a timestamp so new widgets show up. If you build some other way, bump `CURRENT_PROJECT_VERSION`.
- **The old widget extension keeps running after a reinstall** and serves the old code until killed. `make install` handles this.
- **WidgetKit rations reloads.** Calling `reloadTimelines` every poll burns through the daily budget and the widgets freeze. See `Poller.publish` for the throttling. Keep new reload triggers to meaningful changes.
- **Widgets stuck as grey placeholder bars** mean the App Intents index (`linkd`) lost the bundle; the log shows `Missing: com.austinkurpuis.kubewidget:Select…Intent`. `make install` restarts `linkd` to re-index; by hand, run `killall linkd`.
- **`ImageRenderer` can't draw `Link`.** Widget rows use `TapLink`, which renders plain content when the `staticPreview` environment value is set (as the preview tool does).
- **`ViewThatFits` children need unique IDs.** Two `ForEach`s with overlapping integer IDs crash SwiftUI at runtime.
- **The desktop may render widgets tinted or monochrome.** Check `widgetRenderingMode` before drawing fills; see `Sparkline`.
- **Local Network permission** can reset when the app is re-signed. If LAN clusters suddenly time out after an install, re-allow it in System Settings.
- **Your fork's bundle IDs:** set `BUNDLE_ID_PREFIX=com.yourname` for `make install` / `make uninstall` if you want your build to live alongside the upstream one.

## Pull requests

- Keep changes focused, and match the existing style: SwiftUI, small views, comments that explain *why*.
- `make build` must succeed without warnings.
- For visual changes, include before/after PNGs from `make preview` or `make screenshots`. If the README screenshots change, regenerate them with `make screenshots`; they must only ever use demo data.
- Update `CHANGELOG.md` under **Unreleased**.

CI builds every PR unsigned (`SIGN=0 make build`) and renders the demo screenshots to catch layout crashes.

## Releasing

1. Update `MARKETING_VERSION` in `project.yml` and move **Unreleased** in `CHANGELOG.md` under the new version.
2. Commit, then tag: `git tag v1.2.0 && git push --tags`.
3. Create a GitHub release from the tag with the changelog entry.

KubeWidget is distributed as source. Users build and sign it with their own certificate, so there's no notarized binary to upload.
