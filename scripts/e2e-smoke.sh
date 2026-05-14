#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PBW_BIN=${PBW_BIN:-"$(swift build --show-bin-path)/pbw"}

if [[ ! -x "$PBW_BIN" ]]; then
  echo "pbw binary was not found at $PBW_BIN. Run swift build first." >&2
  exit 1
fi

PBW_HOME=$(mktemp -d "${TMPDIR:-/tmp}/pbw-e2e.XXXXXX")
export PBW_HOME
trap 'rm -rf "$PBW_HOME"' EXIT

assert_envelope() {
  local expected_ok=$1
  local expected_code=${2:-}
  ruby -rjson -e '
    expected_ok = ARGV[0] == "true"
    expected_code = ARGV[1]
    object = JSON.parse(STDIN.read)
    abort("schemaVersion mismatch") unless object["schemaVersion"] == "pbw.stable.v1"
    abort("ok mismatch: #{object.inspect}") unless object["ok"] == expected_ok
    if expected_ok
      abort("missing data") unless object.key?("data")
    else
      abort("missing error") unless object.key?("error")
      if !expected_code.empty? && object.dig("error", "code") != expected_code
        abort("error code mismatch: #{object.dig("error", "code")} != #{expected_code}")
      end
    end
  ' "$expected_ok" "$expected_code"
}

run_ok() {
  "$PBW_BIN" "$@" | assert_envelope true
}

run_error() {
  local expected_exit=$1
  local expected_code=$2
  shift 2
  local output
  set +e
  output=$("$PBW_BIN" "$@" 2>&1)
  local status=$?
  set -e
  if [[ $status -ne $expected_exit ]]; then
    echo "$output" >&2
    echo "expected exit $expected_exit, got $status" >&2
    exit 1
  fi
  printf '%s' "$output" | assert_envelope false "$expected_code"
}

run_ok config init --force
run_ok config validate
run_ok diagnostics doctor
run_ok snapshot list
run_ok overlay status
run_error 1 capability_unavailable.space_move space move-window
run_error 2 confirmation_required clipboard clear

mcp_output=$(
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"space.move-window","arguments":{}}}' \
    | "$PBW_BIN" mcp
)

printf '%s' "$mcp_output" | ruby -rjson -e '
  input = STDIN.read
  messages = []
  until input.empty?
    if input.start_with?("Content-Length:")
      header, rest = input.split("\r\n\r\n", 2)
      abort("invalid MCP frame") unless rest
      length = header[/Content-Length:\s*(\d+)/i, 1].to_i
      body = rest.byteslice(0, length)
      messages << JSON.parse(body)
      input = rest.byteslice(length, rest.bytesize - length).to_s
    else
      line, input = input.split("\n", 2)
      messages << JSON.parse(line) unless line.to_s.empty?
      input = input.to_s
    end
  end
  abort("expected 3 MCP responses") unless messages.length == 3
  abort("initialize failed") unless messages[0].dig("result", "protocolVersion")
  tools = messages[1].dig("result", "tools")
  abort("tools/list did not return tools") unless tools.is_a?(Array) && !tools.empty?
  tools.each do |tool|
    abort("missing additionalProperties false") unless tool.dig("inputSchema", "additionalProperties") == false
  end
  envelope = messages[2]["result"]
  abort("MCP tool envelope schema mismatch") unless envelope["schemaVersion"] == "pbw.stable.v1"
  abort("MCP tool call should fail honestly") unless envelope["ok"] == false
  abort("MCP tool error mismatch") unless envelope.dig("error", "code") == "capability_unavailable.space_move"
'

if [[ "${RUN_MAC_UI_TESTS:-}" == "true" ]]; then
  run_ok image --mode screen --path "$PBW_HOME/screen.png"
  run_ok observe see
fi
