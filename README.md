# skills2f

Scaffold a Skills 2.0 factory for either Claude Code or Codex.

## What it generates

For `claude`:

- `CLAUDE.md`
- `agents/`
- `validate.sh`
- `publish.sh`
- `skills/`
- `.env.example`
- `hermit.yaml`

For `codex`:

- `AGENTS.md`
- `.codex/agents/`
- `validate.sh`
- `publish.sh`
- `skills/`
- `.env.example`
- `hermit.yaml`

## Usage

```bash
npx skills2f init-factory mi-proyecto --target claude
npx skills2f init-factory mi-proyecto --target codex
npx skills2f enable-claude-agent-teams
```

The package creates separate outputs for Claude and Codex. There is no `both` target.

For Claude Code, you can enable Agent Teams automatically with:

```bash
npx skills2f enable-claude-agent-teams
```

This updates `~/.claude/settings.json` and sets:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

## Generated structure

```text
skills/<skill-name>/
├── SKILL.md
├── agents/
│   └── openai.yaml
├── scripts/
├── references/
└── assets/
```

## Notes

- `SKILL.md` is required.
- `agents/openai.yaml` is recommended by default.
- The scaffold includes local validation and publish scripts.
- `hermit.yaml` is a Docker Swarm template for a Hermit portal.
- If an API-backed skill uses `mcp2cli`, the generated workflow should declare whether it uses `pip install mcp2cli` or `uvx mcp2cli`.

## Local development

```bash
node bin/skills-2-factory.js init-factory /tmp/example-claude --target claude
node bin/skills-2-factory.js init-factory /tmp/example-codex --target codex
```

## Repository

- Private repo: `aitorroma/skills-2-factory-npm`
