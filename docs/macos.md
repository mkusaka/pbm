# macOS

`pbm` v1 is a Swift Package for macOS 15+. It uses public native APIs only:

- Accessibility: `AXUIElement`
- Capture: `ScreenCaptureKit` and CoreGraphics permission preflight
- Input: `CGEvent`
- App control: `NSWorkspace` and `NSRunningApplication`
- Clipboard: `NSPasteboard`
- UI runtime stubs: AppKit-ready direct/daemon/Bridge command surfaces

## Build

```sh
swift build
swift test
.build/debug/pbm --version
```

The executable is generated at:

```sh
.build/debug/pbm
```

## Permissions

Grant permissions to the executable you run, or to a future signed Bridge app.

- Accessibility: required for AX traversal, menu/dialog operations, window mutation, set-value, and perform-action.
- Screen Recording: required for screenshot and ScreenCaptureKit video capture.
- Input Monitoring / event posting: required for CGEvent input synthesis.
- Clipboard: `NSPasteboard` access may be mediated by macOS. Clipboard clear is destructive and requires confirmation by default.

Check current state:

```sh
pbm doctor
```

Open the Accessibility settings pane:

```sh
pbm bridge open
```

## Validation

```sh
swift build
swift test
pbm doctor
pbm --version
pbm config validate
pbm see
pbm see --bundle-id com.google.Chrome
pbm see --bundle-id com.google.Chrome --window-title Inbox --max-children 50 --timeout 5
pbm see --scope allApps --max-elements 2000
pbm image --mode screen --path /tmp/pbm-screen.png
pbm snapshot list
```

MCP smoke test:

```sh
printf 'Content-Length: 58\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | pbm mcp
```

UI-dependent tests should be added behind:

```sh
RUN_MAC_UI_TESTS=true swift test
```

The checked-in tests intentionally verify the JSON contract and command surface without requiring TCC permission prompts.

## Accessibility Snapshots

`pbm see` traverses the frontmost app's `AXUIElement` tree by default. To inspect another running app without focusing it first, pass one of:

```sh
pbm see --bundle-id com.google.Chrome
pbm see --app-id com.google.Chrome
pbm see --pid 12345
pbm see --app Chrome
pbm see --scope allApps --max-elements 2000
pbm see --bundle-id com.google.Chrome --window-id 12345
pbm see --bundle-id com.google.Chrome --window-title Inbox
```

The snapshot metadata records the requested scope, matched applications, traversal depth, element limit, and whether traversal was truncated.
Pass only one app target selector. Ambiguous app-name or window-title matches are reported as `target_ambiguous` instead of choosing one implicitly.

The AX traversal path is bounded for CLI reliability: bulk attribute reads are used where public APIs allow, visited elements are tracked, children are capped per node, alternate child attributes are inspected, and `AXWindows` / focused elements are included when configured. Defaults are `maxDepth=12`, `maxElementCount=400`, `maxChildrenPerNode=50`, and `timeoutSeconds=8`.

## Modes

- Direct mode: default. Runs each command in the current `pbm` process.
- Daemon mode: `pbm daemon start` starts a same-user Unix-domain-socket daemon for local status/log coordination. No TCP listener is opened.
- Bridge mode: commands exist for the permission-bearing app strategy, but v1 does not ship a signed `Bridge.app`. Bridge-only capabilities return structured `capability_unavailable.*` errors instead of pretending to work.

## Storage

Default state is under:

```sh
~/.pbm/
```

Override for tests:

```sh
PBM_HOME=/tmp/pbm-home pbm config init
```
