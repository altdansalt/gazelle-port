# The Ralph Wiggum loop

A *mostly-deterministic* loop: the control flow is dumb, deterministic bash; only the
agent calls are stochastic. Same input → same orchestration; the harness, not the model,
decides what runs and how it's scored.

```
candidates.json
   │
   ▼
┌──────────────┐   per repo
│ EXPERIMENTER │  (Opus 4.8)  reads repo, lists viable Gazelle approaches,
└──────┬───────┘  emits 1..N experiment specs (approach + initial MODULE.bazel sketch)
       │
       ▼  for each experiment spec
┌──────────────┐
│   harness    │  creates worktree from a shallow clone, on branch exp/<id>
└──────┬───────┘
       │
       ▼
┌──────────────┐
│    JUDGE     │  (Opus 4.8)  writes expectations.json: ordered list of
└──────┬───────┘  {cmd, expect} — bazel build/query/test + expected output predicate
       │
       ▼
┌──────────────┐
│    WORKER    │  (Sonnet 4.6, claude CLI w/ tools)  edits ONLY inside the worktree
└──────┬───────┘  to satisfy expectations; bounded turns; full trace captured
       │
       ▼
┌──────────────┐
│    harness   │  runs expectations.json deterministically → score; saves diff + trace
└──────────────┘
```

## Units

- **Experiment** = `{repo, approach, worktree, MODULE.bazel seed, expectations.json}`.
  Lives in `experiments/<repo-slug>/<approach-id>/`.
- **Expectation** = `{cmd, expect}` where `expect` is a predicate over exit code +
  stdout/stderr (e.g. `exit==0`, `stdout~=/Build completed/`, `query lists //...:all`).
- **Score** = weighted pass-rate over expectations, with tiers:
  `0` nothing builds · `1` deps resolve / gazelle runs · `2` `//...` builds ·
  `3` tests discovered · `4` tests pass. Plus an *edit-cost* penalty (lines/files the
  worker changed beyond the seed — "minor edits" is the whole point).

## Determinism rules

- Harness creates/destroys worktrees, sets the model env, enforces turn/time budgets,
  and runs expectations. The agents never score themselves.
- Every agent invocation writes a trace to `traces/<exp>/<role>.{json,log}` and the
  worker's worktree diff to `experiments/<exp>/worker.diff`.
- Idempotent: re-running an experiment id reuses its dir; `--fresh` wipes it.

## Budgets (defaults; see bin/*.sh)

- Worker: capped wall-clock + max turns; if it exceeds, harness scores what exists.
- Bazel: per-command timeout; network allowed (deps fetch), but toolchains hermetic.

## Outputs that matter

- `experiments/<…>/result.json` — score, tier, edit-cost, expectation-by-expectation.
- `docs/findings.md` — rolled-up patterns: per-language tier reached, recurring failure
  modes, which "minor edits" recur (so they can be templated), refuted/confirmed
  hypotheses.
