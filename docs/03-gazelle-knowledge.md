# Gazelle knowledge & per-language amenability

Working notes on what Gazelle can generate, by ecosystem. Confidence is *prior* belief;
experiments update `docs/findings.md`. Exact BCR versions are intentionally omitted —
resolve the latest at experiment time (`bazel` + Bazel Central Registry); pinning here
would rot.

## How Gazelle works (mental model)

Gazelle is a BUILD-file generator. It walks the source tree, infers targets and their
deps from imports, and writes/updates `BUILD.bazel`. Behaviour is steered by
`# gazelle:` **directives** in BUILD files (e.g. `# gazelle:prefix github.com/org/repo`,
`# gazelle:exclude vendor`, `# gazelle:go_naming_convention`). External deps come from a
**deps extension** fed by the native manifest (`go.mod`, `requirements.txt`, …).

The win condition for us: a small fixed `MODULE.bazel` + a root `BUILD` with the
`gazelle` rule + `bazel run //:gazelle` ⇒ a working build graph, with at most a couple of
hand stubs.

## Tier 1 — Go (native, strongest). Prior: HIGH

- `rules_go` + `gazelle`. bzlmod wiring:
  ```starlark
  bazel_dep(name = "rules_go", version = "…")
  bazel_dep(name = "gazelle", version = "…")
  go_deps = use_extension("@gazelle//:extensions.bzl", "go_deps")
  go_deps.from_file(go_mod = "//:go.mod")
  # use_repo(go_deps, …)   ← can be auto-filled by `bazel mod tidy`
  ```
- Root `BUILD.bazel`:
  ```starlark
  load("@gazelle//:def.bzl", "gazelle")
  # gazelle:prefix github.com/ORG/REPO
  gazelle(name = "gazelle")
  ```
- Flow: `bazel run //:gazelle` → BUILD files; `bazel mod tidy` → `use_repo` lines;
  `bazel build //...` / `bazel test //...`.
- **Known friction:** cgo, `//go:embed`, code-gen (stringer, protoc), build tags,
  `internal/` visibility, vendored deps, and repos whose tests need network/testdata
  paths. These are the interesting failure modes to characterize.

## Tier 1 — Protocol Buffers (native). Prior: HIGH (as a slice)

- Gazelle natively emits `proto_library` (+ `go_proto_library` with rules_go). Great for
  proto-centric repos or the proto slice of a polyglot repo.

## Tier 2 — Python (`rules_python` gazelle plugin). Prior: MEDIUM

- Module `rules_python_gazelle_plugin` + `rules_python`. Generates
  `py_library`/`py_binary`/`py_test`. Needs a pip hub from a requirements lock and a
  `gazelle_python_manifest` (`modules_mapping`) so imports map to wheels.
- **Friction:** unpinned/loose requirements, native extension wheels, namespace
  packages, `conftest.py`/pytest discovery, `src/` layouts, dynamic imports.

## Tier 3 — JavaScript / TypeScript (Aspect). Prior: LOW–MEDIUM

- `aspect_rules_js` (+ `aspect_rules_ts`) with the Aspect JS/TS Gazelle configuration
  (`aspect configure` / the rules_js gazelle extension). Generates `ts_project`,
  `js_library`, and test targets; consumes `pnpm-lock.yaml`.
- **Friction:** package-manager coupling (pnpm strongly preferred), bundler configs,
  monorepo workspaces, TS path aliases, no Node toolchain on host (must come from Bazel).
  Lower confidence + more moving parts → treat as learning probes, not easy wins.

## Tier 3 — JVM (Java/Kotlin, community). Prior: LOW

- `bazel-contrib/rules_jvm` ships a Java Gazelle extension (`java_library`/`java_test`);
  Kotlin via `rules_kotlin` + community gazelle. Maven dep resolution
  (`rules_jvm_external`) is the hard part. Probe, don't bank on.

## Selection implication

Rank candidate languages Go ≫ proto ≳ Python > TS/JS > JVM. Within a language, prefer
**library-shaped** repos (clear package graph, unit tests, few exotic build steps) over
app/framework monorepos with heavy code-gen — those are where "minor edits" breaks down,
which is itself a finding.
