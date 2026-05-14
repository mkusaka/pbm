# pbm

`pbm` currently ships `pbw`, a deterministic macOS desktop automation CLI and MCP stdio server.

The macOS implementation is native Swift and returns the stable JSON contract:

```json
{ "schemaVersion": "pbw.stable.v1", "ok": true, "data": {} }
```

Failures use the same envelope with structured error codes. Commands do not call AI models, agents, model providers, natural-language planners, shell execution tools, or remote public listeners.

## Build

```sh
swift build
swift test
.build/debug/pbw doctor
```

Install the development binary wherever you want the public command name:

```sh
install -m 0755 .build/debug/pbw /usr/local/bin/pbw
```

## Examples

```sh
pbw doctor
pbw config init
pbw see
pbw image --mode screen --path /tmp/pbw-screen.png
pbw window list
pbw app list
pbw clipboard get
pbw snapshot list
pbw mcp
```

## Documentation

- [macOS install, permissions, and validation](docs/macos.md)
- [Command reference](docs/commands.md)
- [MCP setup and tools](docs/mcp.md)
- [Native capability limits](docs/capabilities.md)

## Contract

Every CLI command writes one JSON envelope to stdout.

Success:

```json
{
  "schemaVersion": "pbw.stable.v1",
  "ok": true,
  "data": {}
}
```

Failure:

```json
{
  "schemaVersion": "pbw.stable.v1",
  "ok": false,
  "error": {
    "code": "target_not_found",
    "message": "Target was not found.",
    "details": {},
    "retryHint": "optional"
  }
}
```

Exit codes:

- `0`: success
- `2`: invalid arguments or required confirmation missing
- `1`: permission, target, platform, capability, or internal failure

## Safety

The default config requires `--confirm` for destructive commands when `safety.confirmDestructiveActions` is true. This covers window close, app quit/relaunch, clipboard clear, dialog dismiss, daemon/Bridge uninstall, and disruptive Dock commands.

Tool policy applies to both CLI and MCP:

```json
{
  "policy": {
    "allow": [],
    "deny": ["clipboard.clear"]
  }
}
```
