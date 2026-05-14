---
name: pbm-cli
description: Use when operating the deterministic pbm macOS desktop automation CLI or MCP server to observe Accessibility trees, capture screens, drive input, inspect apps/windows/menus/dialogs, or troubleshoot pbm permissions and snapshots.
---

# pbm CLI

Use `pbm` for deterministic macOS desktop automation. It is not an AI agent and does not run shell commands for the user; it returns structured JSON envelopes that the assistant must inspect before acting.

## Operating Rules

- Prefer `pbm see` for Accessibility-tree state before using screenshots.
- Use `pbm see --bundle-id <bundle-id>` or the alias `pbm see --app-id <bundle-id>`, `pbm see --pid <pid>`, `pbm see --app <name>`, or `pbm see --scope allApps` when the target is not the frontmost app.
- For non-frontmost windows, prefer `pbm see --bundle-id <bundle-id> --window-id <id>` after `pbm window list`; use `--window-title` only when it is unique.
- Pass only one app/window snapshot selector. If `target_ambiguous` is returned, retry with `--pid`, `--bundle-id`, or `--window-id`.
- Use snapshot element IDs first. Query selectors such as `--target-text`, `--target-title`, `--automation-id`, `--role`, and `--index` are fallback paths and must be treated as potentially ambiguous.
- Use `pbm image --mode screen --path <path>` only when visual layout or coordinates are needed.
- Treat every command result as authoritative only after checking `ok`, `schemaVersion`, and either `data` or `error`.
- Do not invent success for `capability_unavailable.*`, `permission_denied.*`, `target_not_found`, or `target_ambiguous`.
- For destructive commands, pass `--confirm` only when the user explicitly authorized that action.
- Keep IPC local. Do not start public TCP listeners or use remote automation channels.
- If Accessibility, Screen Recording, or event-posting permissions are missing, report the exact structured error and suggest `pbm doctor`.

## Common Commands

```sh
pbm doctor
pbm --version
pbm see
pbm see --bundle-id com.google.Chrome
pbm see --bundle-id com.google.Chrome --window-id 12345
pbm see --app-id com.google.Chrome
pbm see --scope allApps --max-elements 2000
pbm image --mode screen --path /tmp/pbm-screen.png
pbm click --target B1
pbm click --target-text "Send"
pbm click --x 100 --y 200
pbm type --text "hello"
pbm hotkey --keys cmd+l
pbm window list
pbm app list
pbm clipboard get
pbm clipboard get --type public.png --output /tmp/clipboard.png
pbm snapshot list
pbm mcp
```

## JSON Contract

Successful commands return:

```json
{ "schemaVersion": "pbm.stable.v1", "ok": true, "data": {} }
```

Failures return:

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

## Workflow

1. Run `pbm doctor` if permissions or behavior are uncertain.
2. Run `pbm see` with the narrowest useful scope.
3. Prefer element IDs from the latest snapshot for clicks and inspections.
4. Use coordinates only when the AX tree lacks a usable element.
5. After input, run `pbm see` or `pbm image` again to verify state.
6. Summarize private screen or clipboard content minimally and only for the user's requested purpose.

## References

- Command reference: `docs/commands.md`
- macOS permissions and validation: `docs/macos.md`
- MCP setup: `docs/mcp.md`
- Capability limits: `docs/capabilities.md`
