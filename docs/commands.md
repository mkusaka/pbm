# Command Reference

All commands return `pbm.stable.v1` JSON envelopes.

## Version

- `pbm --version`
- `pbm version`

Version commands also return a stable JSON envelope with `data.name` and `data.version`.

## Observe

- `pbm see`
- `pbm observe see`
- `pbm see --bundle-id com.google.Chrome`
- `pbm see --app-id com.google.Chrome`
- `pbm see --pid <pid>`
- `pbm see --app Chrome`
- `pbm see --scope allApps --max-elements 2000`
- `pbm see --bundle-id com.google.Chrome --window-id <id>`
- `pbm see --bundle-id com.google.Chrome --window-title Inbox`
- `pbm see --max-depth 12 --max-elements 400 --max-children 50 --timeout 8`
- `pbm image --mode screen --path /tmp/pbm.png`
- `pbm observe image --mode window --window-id <id> --path /tmp/window.png`
- `pbm capture live start`
- `pbm capture live frame --id <session> --path /tmp/frame.png`
- `pbm capture live status`
- `pbm capture live stop --id <session>`
- `pbm capture video start --duration 3 --path /tmp/pbm.mp4`
- `pbm capture video status`
- `pbm capture video stop`

`capture live` uses a deterministic timer-image fallback in direct mode. Background video sessions require a future daemon/Bridge runtime; direct mode supports duration mode.

`see` observes the frontmost app by default. Use `--bundle-id` / `--app-id`, `--pid`, or `--app` to traverse a specific running app's Accessibility tree, or `--scope allApps` for all regular/active apps. Window-scoped snapshots accept `--window-id`, `--window-title`, or `--window-index`. Pass one app target selector at a time; conflicting selectors return `invalid_argument.conflicting_snapshot_target`, and multiple app-name/window-title matches return `target_ambiguous`. `--max-depth`, `--max-elements`, `--max-children`, and `--timeout` override traversal limits for the command.

AX traversal uses bounded public API reads: bulk attribute lookup when available, visited-element tracking, per-node child caps, alternate child attributes such as visible/web/navigation children, application windows, and focused elements. `--web-focus-fallback` is represented in config but defaults off to avoid surprising focus changes.

## Input

- `pbm click --x 100 --y 200`
- `pbm click --target B1`
- `pbm click --target-text "Send"`
- `pbm click --automation-id submit --snapshot <id>`
- `pbm type --text "hello"`
- `pbm press --key return`
- `pbm hotkey --keys cmd+shift+p`
- `pbm scroll --dy -600`
- `pbm drag --from-x 10 --from-y 10 --to-x 300 --to-y 300 --steps 24`
- `pbm move --x 100 --y 200 --duration 0.2`

Input uses `CGEvent` and fails with a permission error if event posting is unavailable. Target resolution checks coordinates first, then snapshot IDs, app/window scope, automation id, exact text/title, fuzzy text/title, role, index, and ambiguity. Ambiguous snapshot queries return `target_ambiguous` with match details instead of picking one implicitly.

## Semantic

- `pbm set-value --focused --value "text"`
- `pbm set-value --target T1 --value "text"`
- `pbm set-value --target-text "Name" --value "text"`
- `pbm perform-action --focused --action AXPress`

AX operations require Accessibility permission. Coordinate-targeted semantic commands fall back to deterministic click/type behavior where applicable.

## Window

- `pbm window list`
- `pbm window focus --window-id <id>`
- `pbm window move --window-id <id> --x 10 --y 10`
- `pbm window resize --window-id <id> --width 800 --height 600`
- `pbm window set-bounds --window-id <id> --x 10 --y 10 --width 800 --height 600`
- `pbm window minimize --window-id <id>`
- `pbm window maximize --window-id <id>`
- `pbm window restore --window-id <id>`
- `pbm window close --window-id <id> --confirm`

`windowId` is the canonical macOS id. `handle` is returned as a compatibility alias.

## App

- `pbm app list`
- `pbm app launch --bundle-id com.apple.TextEdit`
- `pbm app focus --name TextEdit`
- `pbm app switch --name TextEdit`
- `pbm app quit --name TextEdit --confirm`
- `pbm app hide --name TextEdit`
- `pbm app unhide --name TextEdit`
- `pbm app relaunch --name TextEdit --confirm`
- `pbm app open --url https://example.com`

## Menu, Dialog, Clipboard

- `pbm menu list`
- `pbm menu click --title "About TextEdit"`
- `pbm dialog list`
- `pbm dialog click --title OK`
- `pbm dialog input --text value`
- `pbm dialog dismiss --confirm`
- `pbm dialog file choose`
- `pbm dialog file save`
- `pbm dialog file open`
- `pbm clipboard get`
- `pbm clipboard get --type public.png --base64`
- `pbm clipboard get --type public.png --output /tmp/clipboard.png`
- `pbm clipboard set --text value`
- `pbm clipboard set --file-path /tmp/image.png`
- `pbm clipboard set --data-base64 <base64> --type public.data`
- `pbm clipboard clear --confirm`
- `pbm paste`

Specialized file-dialog commands are present in the surface. Direct mode returns a structured capability response when a stable generic implementation is not available.

## Dock, Menu Bar, Spaces

- `pbm dock list`
- `pbm dock click`
- `pbm dock right-click`
- `pbm dock launch --name Safari`
- `pbm dock hide --confirm`
- `pbm dock show --confirm`
- `pbm dock autohide --confirm`
- `pbm dock status`
- `pbm menubar list`
- `pbm menubar click --title File`
- `pbm menubar open --title File`
- `pbm menubar close`
- `pbm space list`
- `pbm space current`
- `pbm space switch --index 2`
- `pbm space move-window`

Dock pinned items, global Dock mutation, Spaces enumeration, and moving arbitrary windows across Spaces are not exposed by stable public macOS APIs. Those commands return `capability_unavailable.*` unless a public best-effort path exists.

## Snapshot, Overlay, Daemon, Bridge, Config

- `pbm snapshot list`
- `pbm snapshot show --id <snapshot>`
- `pbm snapshot inspect --id <snapshot> --target B1`
- `pbm snapshot clean --keep 20`
- `pbm snapshot export --id <snapshot> --path /tmp/snapshot.json`
- `pbm overlay show`
- `pbm overlay hide`
- `pbm overlay status`
- `pbm daemon start`
- `pbm daemon stop`
- `pbm daemon restart`
- `pbm daemon status`
- `pbm daemon logs`
- `pbm daemon install`
- `pbm daemon uninstall --confirm`
- `pbm bridge install`
- `pbm bridge open`
- `pbm bridge status`
- `pbm bridge reset-permissions`
- `pbm bridge uninstall --confirm`
- `pbm config init`
- `pbm config show`
- `pbm config validate`
- `pbm config get safety.confirmDestructiveActions`
- `pbm config set --path safety.confirmDestructiveActions --value false`
- `pbm doctor`

Overlay and Bridge operations that require a persistent app runtime return honest `capability_unavailable.*` responses in direct mode.
