# Command Reference

All commands return `pbw.stable.v1` JSON envelopes.

## Observe

- `pbw see`
- `pbw observe see`
- `pbw image --mode screen --path /tmp/pbw.png`
- `pbw observe image --mode window --window-id <id> --path /tmp/window.png`
- `pbw capture live start`
- `pbw capture live frame --id <session> --path /tmp/frame.png`
- `pbw capture live status`
- `pbw capture live stop --id <session>`
- `pbw capture video start --duration 3 --path /tmp/pbw.mp4`
- `pbw capture video status`
- `pbw capture video stop`

`capture live` uses a deterministic timer-image fallback in direct mode. Background video sessions require a future daemon/Bridge runtime; direct mode supports duration mode.

## Input

- `pbw click --x 100 --y 200`
- `pbw type --text "hello"`
- `pbw press --key return`
- `pbw hotkey --keys cmd+shift+p`
- `pbw scroll --dy -600`
- `pbw drag --from-x 10 --from-y 10 --to-x 300 --to-y 300`
- `pbw move --x 100 --y 200`

Input uses `CGEvent` and fails with a permission error if event posting is unavailable.

## Semantic

- `pbw set-value --focused --value "text"`
- `pbw perform-action --focused --action AXPress`

AX operations require Accessibility permission. Coordinate-targeted semantic commands fall back to deterministic click/type behavior where applicable.

## Window

- `pbw window list`
- `pbw window focus --window-id <id>`
- `pbw window move --window-id <id> --x 10 --y 10`
- `pbw window resize --window-id <id> --width 800 --height 600`
- `pbw window set-bounds --window-id <id> --x 10 --y 10 --width 800 --height 600`
- `pbw window minimize --window-id <id>`
- `pbw window maximize --window-id <id>`
- `pbw window restore --window-id <id>`
- `pbw window close --window-id <id> --confirm`

`windowId` is the canonical macOS id. `handle` is returned as a compatibility alias.

## App

- `pbw app list`
- `pbw app launch --bundle-id com.apple.TextEdit`
- `pbw app focus --name TextEdit`
- `pbw app switch --name TextEdit`
- `pbw app quit --name TextEdit --confirm`
- `pbw app hide --name TextEdit`
- `pbw app unhide --name TextEdit`
- `pbw app relaunch --name TextEdit --confirm`
- `pbw app open --url https://example.com`

## Menu, Dialog, Clipboard

- `pbw menu list`
- `pbw menu click --title "About TextEdit"`
- `pbw dialog list`
- `pbw dialog click --title OK`
- `pbw dialog input --text value`
- `pbw dialog dismiss --confirm`
- `pbw dialog file choose`
- `pbw dialog file save`
- `pbw dialog file open`
- `pbw clipboard get`
- `pbw clipboard set --text value`
- `pbw clipboard clear --confirm`
- `pbw paste`

Specialized file-dialog commands are present in the surface. Direct mode returns a structured capability response when a stable generic implementation is not available.

## Dock, Menu Bar, Spaces

- `pbw dock list`
- `pbw dock click`
- `pbw dock right-click`
- `pbw dock launch --name Safari`
- `pbw dock hide --confirm`
- `pbw dock show --confirm`
- `pbw dock autohide --confirm`
- `pbw dock status`
- `pbw menubar list`
- `pbw menubar click --title File`
- `pbw menubar open --title File`
- `pbw menubar close`
- `pbw space list`
- `pbw space current`
- `pbw space switch --index 2`
- `pbw space move-window`

Dock pinned items, global Dock mutation, Spaces enumeration, and moving arbitrary windows across Spaces are not exposed by stable public macOS APIs. Those commands return `capability_unavailable.*` unless a public best-effort path exists.

## Snapshot, Overlay, Daemon, Bridge, Config

- `pbw snapshot list`
- `pbw snapshot show --id <snapshot>`
- `pbw snapshot inspect --id <snapshot> --target B1`
- `pbw snapshot clean --keep 20`
- `pbw snapshot export --id <snapshot> --path /tmp/snapshot.json`
- `pbw overlay show`
- `pbw overlay hide`
- `pbw overlay status`
- `pbw daemon start`
- `pbw daemon stop`
- `pbw daemon restart`
- `pbw daemon status`
- `pbw daemon logs`
- `pbw daemon install`
- `pbw daemon uninstall --confirm`
- `pbw bridge install`
- `pbw bridge open`
- `pbw bridge status`
- `pbw bridge reset-permissions`
- `pbw bridge uninstall --confirm`
- `pbw config init`
- `pbw config show`
- `pbw config validate`
- `pbw config get safety.confirmDestructiveActions`
- `pbw config set --path safety.confirmDestructiveActions --value false`
- `pbw doctor`

Overlay and Bridge operations that require a persistent app runtime return honest `capability_unavailable.*` responses in direct mode.
