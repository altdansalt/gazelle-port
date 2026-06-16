# gazel-port

**Goal:** Find which popular repos that use a *non-Bazel* build system can be given a
working Bazel build & test suite using **only** Gazelle, Gazelle plugins, and minor
edits — no hand-authoring of large BUILD graphs.

We discover amenable repos, then run a mostly-deterministic "Ralph Wiggum" loop over
them: an **Experimenter** proposes Gazelle approaches, a **Judge** writes expected
`bazel build/query/test` commands and outputs, a **Worker** tries to satisfy them
inside an isolated git worktree, and a deterministic **harness** scores the result.

## TL;DR — what works today

27 experiments across 19 repos / 4 phases. We score each port on a 0–4 **tier** ladder:
**0** nothing · **1** deps resolve / gazelle runs · **2** `bazel build` succeeds ·
**3** tests discovered · **4** tests pass. "Minor edits" = a tiny `MODULE.bazel` seed +
a few `# gazelle:` directives + `bazel mod tidy`, *not* hand-authoring a BUILD graph.

| Ecosystem | Tool / strategy | Best tier | Verdict (one line) |
|-----------|-----------------|:---------:|--------------------|
| **Go** | native `gazelle` | **4** | **Solved.** ~5–15 line seed → tests pass on clean libs (echo, gin, bubbletea, fzf, kratos-root). |
| **C/C++ (source-native)** | `gazelle_cc` | **3** | **Surprise winner.** Real fine-grained `cc_library` graphs that compile on clean libs (zlib, nlohmann/json, hiredis). Needs `# keep`/`resolve` hand-tuning; does *not* scale to giant apps (neovim → tier 1). |
| **C/C++ (foreign wrap)** | `rules_foreign_cc` | **3** | **Reliable, ~4 edits.** Wraps CMake/Make giants (full llama.cpp, jemalloc) into one building target. But it's a coarse artifact wrap — no per-file graph, tests not wired. |
| **Python** | `rules_python` gazelle plugin | **2–3** | Builds `py_library`, discovers tests; heavier "minor edits" (pinned lock + manifest + per-import `# gazelle:resolve`). |
| **Rust** | `gazelle_rust` | **1** | **Least ready.** Won't `bazel build` even a small clean crate (bytes); size isn't the blocker, the plugin wiring is. |
| **TS/JS** | `aspect_gazelle_js` | **0–1** | Weakest. The generator itself won't stand up. |
| **Proto / Java (app)** | native proto / `contrib_rules_jvm` | **1** | Generator runs, but protoc-codegen / Maven wiring exceeds the seed. |

**Two findings that matter most:**

1. **A plugin's *implementation architecture* predicts success better than its target
   language.** Pure-Go plugins (Go, proto, `rules_python`) build and run cleanly.
   Plugins that ship a **native cgo/Rust import-extractor** (`gazelle_py`, `gazelle_ts`,
   `aspect_gazelle_js`) stall at tier 0–1 — they fail to build *themselves* in a hermetic
   env (PIC/lld link errors), regardless of the repo. → For Python, use the `rules_python`
   plugin, **not** `gazelle_py`.

2. **For clean Go, the binding constraint at tier 4 is usually Go-version skew, not
   Bazel.** Gazelle's toolchain forces a modern Go SDK (≥1.24.12); a mature repo's tests
   may assume *old* Go semantics its CI pins. So "build/structure amenability ≫
   full-test-pass amenability," and the residual gap is upstream version debt, not Gazelle.

*Caveat on the tier-4 marks (M1):* some C/C++ tier-4 results were cleared by a
worker-authored smoke test, which proves the toolchain can compile+run a C++ test but is
**not** "the repo's own suite passes." Read tier-4 alongside the per-experiment report.

**Dig deeper:** [`docs/findings.md`](docs/findings.md) (full evidence: F1–F11, hypotheses
H1–H8) · [`data/results.tsv`](data/results.tsv) (per-experiment table) ·
[`docs/06-ruleset-catalog.md`](docs/06-ruleset-catalog.md) (the Gazelle plugin universe) ·
[`docs/00-goals.md`](docs/00-goals.md) · [`docs/01-decisions.md`](docs/01-decisions.md) ·
[`docs/03-gazelle-knowledge.md`](docs/03-gazelle-knowledge.md) ·
[`docs/05-loop-design.md`](docs/05-loop-design.md).

## Layout

| Path | What |
|------|------|
| [`docs/findings.md`](docs/findings.md) | **The evidence log** — every confirmed finding, failure mode, and hypothesis |
| [`docs/06-ruleset-catalog.md`](docs/06-ruleset-catalog.md) | The Gazelle plugin / ruleset universe surveyed |
| [`docs/`](docs/) | [Goals](docs/00-goals.md), [decisions](docs/01-decisions.md), [LLM gateway](docs/02-llm-gateway.md), [Gazelle knowledge](docs/03-gazelle-knowledge.md), [selection method](docs/04-selection-methodology.md), [loop design](docs/05-loop-design.md) |
| [`data/`](data/) | Candidate dataset (`candidates.json`/`.md`) + results table ([`results.tsv`](data/results.tsv)) |
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
