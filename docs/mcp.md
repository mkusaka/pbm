# MCP

`pbw mcp` runs a stdio MCP-compatible JSON-RPC server. It exposes the same command surface as the CLI.

## Start

```sh
pbw mcp
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
    "schemaVersion": "pbw.stable.v1",
    "ok": true,
    "data": {}
  }
}
```

## Policy

The same `policy.allow` and `policy.deny` config is enforced for CLI and MCP. Denied tools return:

```json
{
  "schemaVersion": "pbw.stable.v1",
  "ok": false,
  "error": {
    "code": "tool_denied",
    "message": "Tool is denied by policy.",
    "details": { "tool": "clipboard.clear" }
  }
}
```
