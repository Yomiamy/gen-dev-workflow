<div align="right">
  <strong>English</strong> | <a href="README.zh-TW.md">繁體中文</a>
</div>

# gen-dev-workflow

An end-to-end development workflow orchestrator from feature spec to pull request, packaged as a Claude Code plugin.

In a nutshell: **You say "Build feature X", and it autonomously coordinates planner → implementer → verifier → reviewer → publisher through the entire software lifecycle, pausing only at critical decision points to confirm with you.**

Pause points do not rely on LLM self-discipline; they are strictly enforced by a ratchet state machine via `wf-state.sh`—any unapproved attempt to advance stages is rejected directly by the script.

## Installation

```bash
/plugin marketplace add Yomiamy/gen-dev-workflow
/plugin install gen-dev-workflow
```

For local development and testing, install using your local path:

```bash
/plugin marketplace add /path/to/gen-dev-workflow
```

Upon installation, hooks are automatically mounted via `hooks/hooks.json`—manual entry in `settings.json` is **NOT** required.

## Orchestration Workflow

📊 **[Interactive Workflow Diagram](docs/diagrams/gen-dev-workflow.html)** (Open in browser; includes model, effort, delegation badges, three guided view perspectives, search, and export)

Seven stages with ⏸ denoting pause points (`strict` mode pauses at all gates by default). STAGE 0a→4 constitutes the primary pipeline; STAGE 5 and 6 are standalone entry points triggered manually.

| Stage | Tasks & Responsibilities | Agent / Skill | Model | Effort | Delegation |
|:--|:--|:--|:--|:--|:--|
| **0a** Feature Spec | Dual parallel tracks: Project context gathering / Similar feature code investigation, synthesized into `docs/features/` | planner | `opus` | `xhigh` | ❌ No delegation |
| **0b** Implementation Plan | Data structures, file changes, task breakdown with per-task complexity tags → `docs/plans/` | planner | `opus` | `xhigh` | ❌ No delegation |
| **1** Issue + Worktree | Issue body with 5 standard sections (zh-tw); create worktree + branch following `ticket-id-dev-prep` rules | gen-gh-issue skill + brancher | `sonnet` | `high` | ✦ `gh issue create`, `git worktree add` |
| **2** Implementation | ≥2 independent tasks with non-overlapping write paths → parallel; otherwise sequential | implementer | `sonnet` | `max` | ✦ Code + Tests + Commits |
| **2** Acceptance | Two phases: spec compliance → code quality | verifier | `opus` | `xhigh` | ❌ In-session verification |
| **3** Review | Root cause analysis; never allow the authoring model to review its own code | reviewer | `opus` | `xhigh` | ❌ No delegation |
| **4** Publish | `gen-pr` generates description (Summary + Issues Fixed / Solutions), push + create PR | publisher + gen-pr skill | `sonnet` | `high` | ✦ Diff analysis; executes `gh pr create` directly |
| **5** Respond to Review | Per-comment judgment → reviewer cross-verification → publisher updates PR | responder → reviewer → publisher | `sonnet` / `opus` / `sonnet` | `high` / `xhigh` / `high` | ❌ No delegation |
| **6** Cleanup Worktree | Sync docs back → commit → remove worktree (**branches are always preserved**) | gen-sync-docs-by-branchs → gen-commit → worktree-close-cleanup | — | — | ❌ Run in main session |

### Per-task Tiering in STAGE 2

The implementer does not use the same model tier for all tasks; after reading the implementation plan, it determines delegation per task:

| Complexity Signal | Delegation Tier | Example |
|:--|:--|:--|
| Touches 1–2 files, fully specified, mechanical | Fast / low-cost tier (delegates to internal fast model) | Adding DTO fields, utility functions |
| Touches multiple files, requires integration & coordination | Standard `sonnet` / `max` | Cross-service integration, modifying existing workflows |
| Requires architectural design judgment or deep codebase understanding | Strongest reasoning `opus` / `xhigh` | Refactoring state machines, introducing cross-cutting layers |

> ⚠️ **Effort must be explicitly passed during dispatch.** Commit `a6fcd29` removed `effort:` from individual agent frontmatters; subagents inherit the main session's current effort by default. Omitting the `effort` parameter means the stage-differentiated efforts in the table above **will NOT take effect**, falling back entirely to the session default.

### Hard Rules: When NOT to Delegate

Even if MCP delegation is available, the following must never be delegated:
- STAGE 3 review reports (reviewer evaluates directly)
- External modifying actions (`gh pr create` / `git push`)
- Commit message generation
- Small fixes under 50 lines in a single file

### Two Distinct Feedback Loops

- **STAGE 2 Internal Retry**: 2 failures within the same tier → escalate one tier for 1 retry (maximum of one tier escalation). Infrastructure errors (400 effort/thinking, 429, 5xx, disconnections) **do not count toward the failure threshold**—switching to a stronger model does not fix infrastructure errors.
- **STAGE 3 Rejection**: The entire stage returns to STAGE 2 for rework only if review fails.

These two loops must not be conflated. Additionally, **Proactive Interruption**: When token context exceeds 150k, the Token Budget Gate pauses and migrates to a new session, resuming directly at the current stage.

### Parallel Acceleration (Opt-in Required)

Enabled only when explicitly requested (e.g., saying "ultracode", "use workflow", or "multi-agent"). Otherwise, execution falls back to sequential `Task(...)` calls with identical functionality. Only three places support parallel execution:
1. STAGE 0a dual-track context gathering
2. STAGE 2 concurrent independent tasks
3. STAGE 3 multi-angle adversarial review

**Never** wrap the entire orchestrator into a single background Workflow—background Workflows execute headlessly without user interaction, which completely breaks all human-in-the-loop pause gates.

Detailed stage rules are located in `skills/gen-dev-workflow/references/`: `state-machine.md`, `delegation-and-parallel.md`, `branch-worktree-rules.md`, `token-budget-gate.md`, `execution-modes.md`, and `mcp-delegation-discipline.md`.

## Dependencies

| Dependency | Requirement | Purpose |
|:---|:---|:---|
| `jq` | **Required** | Handles all JSON state read/write operations in `wf-state.sh` |
| `gh` CLI | Required for STAGE 1 & 4 | Creates GitHub issues and pull requests |
| `git` ≥ 2.5 | Required | Git worktree support |
| `gemini-mcp-tool` | Optional | Used for agent delegation; falls back to main session if unavailable |

## Repository Structure

```
skills/gen-dev-workflow/     Core orchestrator: SKILL.md + 8 reference docs + wf-state.sh
skills/ (remaining 15)       Supporting skills: gen-pr / gen-commit / gen-gh-issue /
                             ticket-id-dev-prep / worktree-close-cleanup, etc.
agents/                      7 specialized roles: planner / implementer / verifier /
                             reviewer / publisher / brancher / responder
hooks/                       stage-check (ratchet enforcement) + delegate-cwd (delegation boundary sandbox)
tests/                       Tier 1 state machine + Tier 2 hook pure functions
examples/sandbox/            Tier 3 mock project for end-to-end smoke testing
docs/diagrams/               Interactive workflow diagrams (.workflow.json spec + .html)
```

## Testing

```bash
./tests/run-all.sh          # Runs Tier 1 + Tier 2 tests (~2 seconds)
```

Three-tier testing strategy:

| Tier | Target | Automation |
|:--|:--|:--|
| 1 | `wf-state.sh` state machine invariants (ratchet, invalid transitions, `pause_level`, batch cursor) | ✅ 35 assertions |
| 2 | Hook pure functions (allowlist, path checking, diff computation) | ✅ |
| 3 | End-to-end wiring (skill loading, agent dispatch, hook interception) | ❌ Manual, see `examples/sandbox/README.md` |

Tier 3 is intentionally not automated: the subject under test is Claude's behavior after reading `SKILL.md`. The cost of mocking the entire execution environment far exceeds the validation value. Running quick mode manually once after modifying workflows is sufficient.

## Usage

```bash
/gen-dev-workflow Build feature X          # Full workflow
/gen-dev-workflow quick Fix Y              # Quick path: single pause point, no worktree
/gen-dev-workflow Develop issue #42        # Skip planning, jump directly to STAGE 1
/gen-dev-workflow batch A B C              # Batch mode: separate worktree/branch/PR for each
```

Adjust pause frequency using `pause_level`:
- `strict` (default, pauses at all gates)
- `balanced` (pauses only at plan approval, implementation completion, and before PR creation)
- `autonomous` (no pauses; allows `gh pr create` to execute without confirmation; requires prior warning)

See `skills/gen-dev-workflow/references/command-cheatsheet.md` for the complete command cheatsheet.

## Where State is Stored

The scripts live in the plugin directory, while **state lives inside your project**—deliberately decoupled:

- State files: `.claude/workflow-state/` in current working directory (overridable via `WF_STATE_DIR`)
- Worktrees: `.claude/worktrees/` in current repository

From STAGE 1 onward, each workflow runs inside its own worktree, keeping state files naturally isolated and allowing multiple concurrent workflows within the same repository.
