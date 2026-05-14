# pbm

`pbm` is a deterministic macOS desktop automation CLI and MCP stdio server.

The macOS implementation is native Swift and returns the stable JSON contract:

```json
{ "schemaVersion": "pbm.stable.v1", "ok": true, "data": {} }
```

Failures use the same envelope with structured error codes. Commands do not call AI models, agents, model providers, natural-language planners, shell execution tools, or remote public listeners.

## Build

```sh
swift build
swift test
.build/debug/pbm doctor
```

Install the development binary wherever you want the public command name:

```sh
install -m 0755 .build/debug/pbm /usr/local/bin/pbm
```

## Examples

```sh
pbm doctor
pbm config init
pbm see
pbm see --bundle-id com.google.Chrome
pbm see --app-id com.google.Chrome
pbm see --scope allApps --max-elements 2000
pbm image --mode screen --path /tmp/pbm-screen.png
pbm window list
pbm app list
pbm clipboard get
pbm snapshot list
pbm mcp
```

## Documentation

- [macOS install, permissions, and validation](docs/macos.md)
- [Command reference](docs/commands.md)
- [MCP setup and tools](docs/mcp.md)
- [Agent skill install](docs/skills.md)
- [Native capability limits](docs/capabilities.md)

## Contract

Every CLI command writes one JSON envelope to stdout.

Success:

```json
{
  "schemaVersion": "pbm.stable.v1",
  "ok": true,
  "data": {}
}
```

Failure:

```json
{
  "schemaVersion": "pbm.stable.v1",
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
