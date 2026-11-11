# Project skills

Every `<name>/SKILL.md` here loads automatically in Claude Code sessions opened from this repo. Call one with `/<name>`.

| Skill | Source | License | Version / fetched | Notes |
|-------|--------|---------|-------------------|-------|
| `ponytail` | https://github.com/DietrichGebert/ponytail (`skills/ponytail/SKILL.md`) | MIT | `main`, fetched 2026-10-28 | Smallest-change mode. `/ponytail lite\|full\|ultra\|off`. Prompt only, no hooks or scripts. The plugin's other commands (e.g. `/ponytail-help`) are not vendored. |
| `reverse-engineer-anything` | Origin not recorded when added (commit `bc6ad93`) | See `reverse-engineer-anything/LICENSE` | `metadata.version: "49"` | Reverse engineering with REA. Has `references/` files. |
| `agent-browser` | https://github.com/vercel-labs/agent-browser (`skills/agent-browser/SKILL.md`) | Apache-2.0 | `main`, fetched 2026-10-28 (CLI v0.40.0) | Discovery stub only. Needs the CLI: `npm i -g agent-browser && agent-browser install`; then `agent-browser skills get core`. Not installed in cloud sessions by default. |

## Adding a skill

1. Copy it to `.claude/skills/<name>/` (keep `SKILL.md`, `LICENSE` and any `references/`).
2. Read it first. A skill is instructions Claude follows, and this repo touches live-trading code.
3. Add a row above: source URL, license, version or fetch date.
4. Skill names must be unique.

## Limits

- Only sessions opened from this repo see these skills. Other repos and plain claude.ai chats need their own copy.
- `/plugin` is unavailable in cloud sessions, so plugin-only features (marketplace commands, hooks) are not installed.
