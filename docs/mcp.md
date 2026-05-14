# MCP

`pbm mcp` runs a stdio MCP-compatible JSON-RPC server. It exposes the same command surface as the CLI.

## Start

```sh
pbm mcp
```

The server supports:

- `initialize`
- `tools/list`
- `tools/call`

Each `tools/call` result is the same stable envelope returned by the CLI.

## Tool Schema

Every tool schema is an object schema with:

```json
{
  "type": "object",
  "additionalProperties": false,
  "properties": {}
}
```

The property set is intentionally shared and conservative. Unknown properties are rejected by MCP clients that honor the schema.

`observe.see` accepts the same snapshot selectors as the CLI:

- `bundle-id` / `bundleId` / `app-id` / `appId`: exact running app bundle identifier.
- `pid`: exact process id.
- `app`: running app name substring.
- `scope`: `frontmost` or `allApps`.
- `window-id` / `window-title` / `window-index`: window-scoped AX traversal.
- `max-depth` / `maxDepth`: per-call AX traversal depth.
- `max-elements` / `maxElementCount`: per-call element limit.
- `max-children` / `maxChildren`: per-node child cap.
- `timeout` / `timeout-seconds`: traversal deadline.

Pass only one app target selector. Conflicts return `invalid_argument.conflicting_snapshot_target`; multiple app-name or window-title matches return `target_ambiguous`.

Input and semantic tools expose snapshot target selectors such as `target`, `target-text`, `target-title`, `automation-id`, `role`, and `index`; semantic tools also expose `value`, `action`, and `focused`. Window tools expose `window-id`, `windowId`, and `handle`. Clipboard tools expose typed data options such as `type`, `uti`, `base64`, `output-path`, `file-path`, `data-base64`, and `max-bytes`.

## Example

Initialize:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {}
}
```

Call a tool:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "window.list",
    "arguments": {}
  }
}
```

Result:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "schemaVersion": "pbm.stable.v1",
    "ok": true,
    "data": {}
  }
}
```

## Policy

The same `policy.allow` and `policy.deny` config is enforced for CLI and MCP. Denied tools return:

```json
{
  "schemaVersion": "pbm.stable.v1",
  "ok": false,
  "error": {
    "code": "tool_denied",
    "message": "Tool is denied by policy.",
    "details": { "tool": "clipboard.clear" }
  }
}
```
