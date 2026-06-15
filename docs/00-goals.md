# Goals

## North star

Determine, empirically, **which categories of popular non-Bazel repos can be ported to
a working Bazel build+test suite using only Gazelle (+ plugins) and minor edits.**

"Working" = a deterministic harness can run a set of expected `bazel build`, `bazel
query`, and `bazel test` commands and observe expected outputs (targets exist, build
succeeds, tests pass / are discovered).

"Minor edits" = bounded, mechanical changes: adding `MODULE.bazel`, a `BUILD` stub or
two, `.bazelrc`, gazelle directives (`# gazelle:` comments), a deps-extension lockfile.
**Not** minor: hand-writing the bulk of the BUILD graph, patching upstream source logic,
rewriting the project's layout.

## Why

Gazelle automates the tedious part of Bazel adoption (BUILD file generation). If we can
characterize *which repos it carries across the finish line with little help*, that is a
concrete, reusable answer about Bazel's real-world onboarding cost per ecosystem.

## What we produce

1. A ranked, annotated **candidate set** of active, amenable repos (`data/`).
2. Per-repo **experiments** (worktree + MODULE.bazel + expectations + score + trace).
3. A growing **findings** doc: which approaches work, common failure modes, per-language
   success rates, and hypotheses to test next.

## Bias / strategy

- **Active repos** (many PRs, many commits, recent pushes) — maximize learning and
  relevance; avoid abandoned code.
- **Gazelle-amenable languages first:** Go (native, strongest) > Protobuf (native) >
  Python (`rules_python` gazelle plugin) > JS/TS (`aspect rules_js` gazelle). See
  `docs/03-gazelle-knowledge.md`.
- **Exclude repos that already use Bazel** (presence of `MODULE.bazel`/`WORKSPACE*`).
- Prefer real buildable code over awesome-lists / docs / books (a large fraction of the
  literal "top by stars" set is non-code).

## Non-goals

- Porting an entire monorepo perfectly. We measure *how far Gazelle gets us cheaply*.
- Beating a repo's existing build on speed/features. Correctness of a minimal slice is
  the bar.
