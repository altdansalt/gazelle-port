# Findings

Rolling, evidence-backed record. Each finding cites the experiment(s) that produced it.
Hypotheses live at the bottom until confirmed/refuted.

## Summary scoreboard

| Language | Experiments | Best tier reached | Notes |
|----------|-------------|-------------------|-------|
| Go       | 0           | –                 | pending |
| Python   | 0           | –                 | pending |
| TS/JS    | 0           | –                 | pending |
| Proto    | 0           | –                 | pending |

Tiers: 0 nothing · 1 deps/gazelle run · 2 `//...` builds · 3 tests discovered · 4 tests pass.

## Confirmed findings

_(none yet)_

## Failure modes observed

_(none yet)_

## Recurring "minor edits" (candidates to templatize)

_(none yet)_

## Hypotheses (to confirm/refute)

- **H1.** A flat-layout Go library with a root `go.mod`, no cgo, and stdlib-only or
  few deps reaches tier 4 with only `MODULE.bazel` + root `gazelle` BUILD + `bazel run
  //:gazelle` + `bazel mod tidy`. _Prior: high._
- **H2.** cgo, `//go:embed`, and code-gen (stringer/protoc) are the dominant Go blockers,
  each requiring a specific known edit. _Prior: high._
- **H3.** Python repos need a pinned requirements lock to reach tier 2; loose/unpinned
  deps stall at tier 1. _Prior: medium._
- **H4.** TS/JS only reaches tier ≥2 when the repo already uses pnpm. _Prior: medium._
- **H5.** Repo `size` and code-gen topics predict failure better than star count.
  _Prior: medium._
