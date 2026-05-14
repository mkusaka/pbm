# Agent Skill

`skills/pbm-cli/SKILL.md` teaches coding agents how to use the installed `pbm` CLI without copying a stale command reference into every prompt.

## Install

From a published GitHub repository:

```sh
npx skills add mkusaka/pbm -s pbm-cli
```

For non-interactive Codex setup:

```sh
npx skills add mkusaka/pbm -s pbm-cli -a codex -y
```

For non-interactive Claude Code setup:

```sh
npx skills add mkusaka/pbm -s pbm-cli -a claude-code -y
```

From a local checkout while developing the skill:

```sh
npx skills add . -s pbm-cli -a codex -y
```

Claude Code also supports project skills directly under `.claude/skills/<skill-name>/SKILL.md`; this repository keeps the distributable skill under `skills/pbm-cli/` so the same directory can be installed by skill managers.

To avoid package-manager telemetry during local installation, prefix the command with `DISABLE_TELEMETRY=1`.

## Prerequisites

Install or build `pbm` first:

```sh
swift build
install -m 0755 .build/debug/pbm /usr/local/bin/pbm
pbm doctor
```

Grant macOS Accessibility, Screen Recording, and event-posting permissions to the executable or Bridge app that will run commands.

## Maintenance

Keep the skill thin. It should point agents at live `pbm` JSON output and canonical docs instead of embedding a generated per-command reference that can drift.
