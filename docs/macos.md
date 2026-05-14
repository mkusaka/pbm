# macOS

`pbw` v1 is a Swift Package for macOS 15+. It uses public native APIs only:

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
```

The executable is generated at:

```sh
.build/debug/pbw
```

## Permissions

Grant permissions to the executable you run, or to a future signed Bridge app.

- Accessibility: required for AX traversal, menu/dialog operations, window mutation, set-value, and perform-action.
- Screen Recording: required for screenshot and ScreenCaptureKit video capture.
- Input Monitoring / event posting: required for CGEvent input synthesis.
- Clipboard: `NSPasteboard` access may be mediated by macOS. Clipboard clear is destructive and requires confirmation by default.

Check current state:

```sh
pbw doctor
```

Open the Accessibility settings pane:

```sh
pbw bridge open
```

## Validation

```sh
swift build
swift test
pbw doctor
pbw config validate
pbw see
pbw image --mode screen --path /tmp/pbw-screen.png
pbw snapshot list
```

MCP smoke test:

```sh
printf 'Content-Length: 58\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | pbw mcp
```

UI-dependent tests should be added behind:

```sh
RUN_MAC_UI_TESTS=true swift test
```

The checked-in tests intentionally verify the JSON contract and command surface without requiring TCC permission prompts.

## Modes

- Direct mode: default. Runs each command in the current `pbw` process.
- Daemon mode: `pbw daemon start` starts a same-user Unix-domain-socket daemon for local status/log coordination. No TCP listener is opened.
- Bridge mode: commands exist for the permission-bearing app strategy, but v1 does not ship a signed `Bridge.app`. Bridge-only capabilities return structured `capability_unavailable.*` errors instead of pretending to work.

## Storage

Default state is under:

```sh
~/.pbw/
```

Override for tests:

```sh
PBW_HOME=/tmp/pbw-home pbw config init
```
