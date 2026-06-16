# Phase 2 — beyond Go: the frontier batch

Phase 1 established Go is a near-solved tier-4 case (testify tier 3 by version-skew;
echo/gin/bubbletea/fzf/kratos tier 4). Phase 2 targets the *interesting* question:
**what does the rest of the ruleset ecosystem actually achieve today?**

## Mapping the owner's repo lists → strategy

| Repo | Build | Strategy | Plugin/ruleset | Prior |
|------|-------|----------|----------------|-------|
| redis/redis | make | **B** foreign | `rules_foreign_cc` (configure-make) | med — small, famous |
| ggml-org/llama.cpp | cmake | **A** & **B** | `gazelle_cc` vs `rules_foreign_cc` | low/med — A-vs-B compare |
| astral-sh/uv | cargo | **A** | `gazelle_rust` + `rules_rust` | low — big workspace |
| astral-sh/ruff | cargo | **A** | `gazelle_rust` + `rules_rust` | low — big workspace |
| microsoft/TypeScript | npm/TS | **A** | `aspect_gazelle_js` | low — huge |
| excalidraw/excalidraw | npm/TS | **A** | `aspect_gazelle_js` | low/med |
| neovim, clickhouse, vim, julia, cpython | cmake/make | **B** | `rules_foreign_cc` | med (coarse) |
| ziglang/zig, ghostty | zig | manual | `rules_zig` (no gazelle) | low |
| prometheus, grafana, moby, kubernetes | go | A | `gazelle` (known) | high but known |
| protobuf, grpc, openai/codex | **already Bazel** | — | study as reference | — |

## Wave 2 batch (frontier, ~5 repos)

Chosen to span the frontier and produce the clearest "achievable now" signal:

1. **redis/redis** — `rules_foreign_cc` configure-make. The cleanest Strategy-B probe.
2. **ggml-org/llama.cpp** — run BOTH `gazelle_cc` (A) and `rules_foreign_cc` (B); direct
   comparison of the two C/C++ deliverables on one repo.
3. **astral-sh/uv** — `gazelle_rust`. The headline Rust probe.
4. **microsoft/TypeScript** — `aspect_gazelle_js`. The headline TS probe.
5. (stretch) **astral-sh/ruff** — second Rust data point if time/disk allow.

Expect lower tiers than Go — that's the finding. A tier-2 build via `gazelle_rust` on uv,
or a tier-2 foreign_cc wrap of redis, is a *positive* result for "what's achievable now."

## Harness changes required

- Experimenter prompt → **multi-ecosystem**: fed `docs/06` catalog + `data/bcr-versions.json`;
  selects Strategy A (which gazelle plugin) or B (foreign_cc) per language; emits the
  right `MODULE.bazel` (plugin bazel_dep + extension wiring) and setup commands. Keep the
  Go hard-won rules; add per-ecosystem gotchas as we learn them.
- Judge → expectations already strategy-agnostic (build/query/test ladder). For Strategy B,
  tier-2 = the foreign target builds; tier-4 = the project's own test target (if wrapped).
- Scoring/disk hygiene unchanged (foreign_cc builds can be large → expunge still applies).
