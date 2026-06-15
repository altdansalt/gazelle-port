# gazel-port

**Goal:** Find which popular repos that use a *non-Bazel* build system can be given a
working Bazel build & test suite using **only** Gazelle, Gazelle plugins, and minor
edits — no hand-authoring of large BUILD graphs.

We discover amenable repos, then run a mostly-deterministic "Ralph Wiggum" loop over
them: an **Experimenter** proposes Gazelle approaches, a **Judge** writes expected
`bazel build/query/test` commands and outputs, a **Worker** tries to satisfy them
inside an isolated git worktree, and a deterministic **harness** scores the result.

## Status

Bootstrapped 2026-06-15 (overnight autonomous run). See `docs/` for the live record of
goals, decisions, findings, and hypotheses, and `data/` for the candidate repo set.

## Layout

| Path | What |
|------|------|
| `docs/` | Goals, decision log, gateway facts, Gazelle knowledge, methodology, loop design |
| `data/` | Generated candidate repo dataset (`candidates.json`, `candidates.md`) |
| `bin/` | Orchestration scripts (selection, LLM helper, experiment runner, the loop) |
| `prompts/` | System prompts for the experimenter / judge / worker agents |
| `experiments/` | Per-experiment worktrees + records (generated) |
| `traces/` | Raw agent transcripts and edit diffs (generated) |

## Conventions

- **Bazel for the experiments.** Every experiment's build/test must run under Bazel
  with hermetic toolchains (no host Go/Python/Node). See `docs/01-decisions.md`.
- **Blessed host tools only:** `git`, `gh`, `bash`, `curl`, `bazel`, and the `claude`
  CLI. Everything else comes from Bazel.
- **Record everything.** Decisions go in `docs/01-decisions.md`; findings accrue in
  `docs/findings.md`; every agent run leaves a trace under `traces/`.

## Running

```bash
bin/select-repos.sh        # (re)build the candidate dataset from the GitHub API
bin/ralph-loop.sh          # run the experiment loop over queued repos
```
