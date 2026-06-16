# Findings

Rolling, evidence-backed record. Each finding cites the experiment(s) that produced it.
Hypotheses live at the bottom until confirmed/refuted.

## Summary scoreboard (16 experiments across 11 repos, 2 phases)

| Ecosystem | Strategy / ruleset | n | best | mean | Verdict |
|-----------|--------------------|---|------|------|---------|
| **Go** | A `gazelle` (native) | 7 | **4** | 3.7 | **Solved.** 5/6 tier 4 with ~5–15 line seeds. |
| **C/C++** | A `gazelle_cc` | 2 | **4** | — | **Surprise winner.** Generates real building cc_library graphs (tier 2–3 genuine; tier 4 on a slice + worker test). F6 |
| **C/C++** | B `rules_foreign_cc` | 3 | **3** | — | **Reliable.** Builds real artifacts (full libllama, jemalloc) with ~4 edits; coarse. F7 |
| **Python** | A `rules_python` plugin | 1 | **2** | 2.0 | Library builds; tests exceed minor edits. F4 |
| **Rust** | A `gazelle_rust` | 1 | **1** | 1.0 | Generates BUILDs on big workspace but build fails. F8 |
| **TS/JS** | A `aspect_gazelle_js` | 2 | **1** | 0.5 | Generator won't run (native extractor). F5/F9 |

Tiers: 0 nothing · 1 deps/gazelle run · 2 builds · 3 tests discovered · 4 tests pass.
Full per-experiment table: `data/results.tsv` / `bin/rollup.sh`.

> **Headline answer to "what's achievable now":**
> **Go ≫ C/C++ > Python > Rust > TS** for *Gazelle* (source-native, fine-grained).
> Separately, **`rules_foreign_cc` reliably gets CMake/Make C/C++ giants to a building
> Bazel target with ~4 edits** (Strategy B) — it genuinely "does most of the work," but
> the deliverable is one coarse wrapping target, not a native graph. The night's biggest
> surprise: **`gazelle_cc` is far more capable than its ★42 suggests** — on clean C
> libraries it produced a fine-grained, *buildable* C++ graph and out-performed foreign_cc.

## Confirmed findings

### F1 — A clean Go library Bazel-ports to tier 3 with a ~15-line seed + 2 fixes (HIGH confidence)
**Evidence:** `stretchr/testify` (manual run, harness-mechanism validation).
Seed = `MODULE.bazel` (rules_go 0.61.1 + gazelle 0.51.3 + `go_sdk` + `go_deps.from_file`),
a 4-line root `BUILD.bazel` (`gazelle` rule + `# gazelle:prefix` + 2 `# gazelle:exclude`),
and `.bazelrc`. Flow: `bazel run //:gazelle` (generated 10 BUILD files) → `bazel mod tidy`
→ `bazel build //...` **succeeded (19 targets)** → `bazel test //...` = **6/8 targets PASS**.
So: build is a non-event for clean Go; the interesting line is at *tests*.

### F2 — The Go SDK pin is the #1 gotcha, and the repo's go.mod version is the WRONG value (HIGH)
**Evidence:** testify go.mod says `go 1.17`. Seeding `go_sdk.download("1.17")` fails:
`flag provided but not defined: -buildvcs` (that flag needs Go ≥1.18). Bumping to `1.24.4`
then fails: `go.work requires go >= 1.24.12` (gazelle's *own* build tools). `1.25.4` works.
Lesson: **pin a recent stable Go SDK (≥ gazelle's floor, currently 1.24.12), independent
of the repo's declared minimum** — Go is backward compatible. Now encoded in the
experimenter prompt and seed.

### F3 — The binding tier-4 constraint is often *Go-version skew*, not Bazel (HIGH, important)
**Evidence:** `stretchr/testify` automated run (worker = Sonnet 4.6). The worker reached
tier 3 and diagnosed the exact tier-4 blocker: **Go 1.21 changed `panic(nil)` semantics**
— `recover()` now returns `*runtime.PanicNilError{}` instead of `nil` — and testify's own
tests assert `msg == nil` after `panic(nil)`; its `suite` tests call `testing.RunTests`
internally in ways whose failures now propagate to the binary exit code.
**The general principle:** Gazelle's toolchain forces a *modern* Go SDK (≥1.24.12, F2),
but a mature repo's tests may be written for *old* Go semantics that its own CI preserves
by pinning an ancient `go` directive. Building hermetically with a modern SDK surfaces
latent, pre-existing version incompatibilities. So the realistic ceiling for "Gazelle +
minor edits" on such repos is **tier 3 + most of tier 4**, with a tail of tests that fail
for reasons *unrelated to Bazel/Gazelle* — they'd fail under `go test` on a modern Go too.
This reframes "amenability": **build/structure amenability ≫ full-test-pass amenability**,
and the gap is usually upstream version debt, not Gazelle.
> Methodological note: this is why the harness scores *tiers*, not pass/fail. Tier 3 with
> a clean diagnosis is a success for our research question.

### F4 — Python reaches tier 2 (build) with rules_python + gazelle; tests need more (MEDIUM)
**Evidence:** `pallets/flask` (Strategy A). Worker reached tier 2 for `//src/...`: generated
`requirements.lock` (`uv export`), created the `gazelle_python.yaml` manifest
(`bazel run //:gazelle_python_manifest.update`), and added `# gazelle:resolve` directives
for imports gazelle can't map (`_typeshed.wsgi` under `TYPE_CHECKING`). The library
(`py_library` at `//src/flask`, `/json`, `/sansio`) builds. **But** flask's tests live in
`tests/` with cross-package app fixtures (`blueprintapp`, relative imports) gazelle can't
resolve without substantial hand directives, so test tiers were (correctly) scoped out /
made informational. So the realistic Python ceiling here is **tier 2**, and the "minor
edits" are heavier than Go: a pinned lock + a manifest + per-import resolve directives.

### F5 — TS/JS Gazelle can't even *run* today: the plugin's native extractor won't build (MEDIUM)
**Evidence:** `pmndrs/zustand` (Strategy A, `aspect_gazelle_js`). `bazel mod graph` resolved
(tier 1 partial) but `bazel run //:gazelle` failed: the JS/TS gazelle ships a **native
(Rust/cgo) TypeScript import-extractor** that must compile, and its toolchain (LLVM/rustlib)
wouldn't build in this hermetic env. The worker spent its entire 25-min budget yak-shaving
the *plugin's own build* and never generated a BUILD file → **tier 1**, worker timeout
(exit 124). Implication: TS-via-Gazelle's first hurdle isn't your repo, it's standing up
the generator. Phase 2 will see if `microsoft/TypeScript` hits the same wall (expected).

### F6 — `gazelle_cc` generates real building C/C++ graphs (the surprise) (HIGH)
**Evidence:** `redis` (deps/hiredis) and `llama.cpp` (common/) both via `gazelle_cc` v0.6.0.
On *both*, gazelle_cc generated fine-grained `cc_library`/`cc_binary` targets that
**compile** — tier 2–3 is genuine, and it *beat* `rules_foreign_cc` on the same repos
(tier 4 vs 3). This is remarkable for an emerging ★42 plugin: source-native C++ BUILD
generation actually works on clean libraries.
**Honest caveats on the tier-4 mark:** (1) scope was a self-contained *slice* (hiredis
client lib; llama.cpp's `unicode` sublib) — the full trees need headers (`llama.h`,
`openssl/ssl.h`) outside scope; (2) tier-4 "tests pass" was cleared by a **worker-authored
26-line smoke test** (the repos' real tests need a running server / core API) — see M1;
(3) it needed real hand-tuning: `# keep` for `#include "x.c"` textual headers,
`# gazelle:resolve cc`, `includes = [".."]` to avoid `string.h` shadowing. So: **genuine
tier 2–3 capability; tier 4 = gazelle_cc + moderate hand-tuning on a chosen slice.**

### F7 — `rules_foreign_cc` reliably reaches tier 3 on CMake/Make giants (HIGH)
**Evidence:** `jemalloc` (configure_make), `hiredis` (cmake), **full `llama.cpp`** (cmake →
`//:llama_cpp`). Each: `bazel build` succeeds and produces real outputs (static libs,
libllama) with only **~4 edits** (a MODULE.bazel + a `cmake()`/`configure_make()` target).
Capped at tier 3 *honestly*: it's a coarse single wrapping target — no fine-grained graph,
no per-file incrementality, tests not wired (would need a separate test rule). This is the
direct answer to "can a ruleset do most of the work?": **yes, for foreign C/C++ builds,
with minimal edits — but it's a build-artifact wrap, a weaker claim than a Gazelle port.**

### F8 — `gazelle_rust` runs but stalls at tier 1 on a large workspace (MEDIUM)
**Evidence:** `astral-sh/uv` (`//crates/...`). `gazelle_rust` v0.1.0 + `rules_rust`
generated **124 BUILD files** (gazelle ran — tier 1) but `bazel build` failed and the
worker timed out (exit 124). uv is a big multi-crate workspace with proc-macros/build.rs;
the plugin + crate_universe wiring didn't converge within budget. Rust-via-Gazelle is real
but not yet turnkey for large repos. (A smaller cargo lib is the fairer next probe.)

### F9 — TS/JS Gazelle is the weakest; on the headliner it reached tier 0 (MEDIUM)
**Evidence:** `microsoft/TypeScript` (`aspect_gazelle_js`) → **tier 0** (worse than
zustand's tier 1) — couldn't even get deps/gazelle to a working state, worker timed out.
Confirms F5 at scale: the JS/TS gazelle's native extractor + pnpm coupling make standing
up the generator the dominant blocker. TS is currently the least-ready ecosystem.

## Failure modes observed

### FM3 — Harness bug (FIXED): `git ls-files | head -N` SIGPIPE under `pipefail`
Lost 2 experiments (gitleaks, kratos's 2nd approach): `head` closes the pipe at N lines,
`git` gets SIGPIPE (141), `pipefail` propagates it, `set -e` aborts the experiment. Racy
(buffering-dependent) so it hit only repos with >N files, intermittently. Fixed by
`|| true` on the substitution in `run-experiment.sh` and `ralph-loop.sh`. *Lesson logged
because the loop must be deterministic; a flaky truncation silently dropped results.*

## Methodology caveats

### M1 — Workers can clear test tiers by authoring trivial tests (TIGHTEN THE JUDGE)
The judge's tier-3/4 expectations ("tests of the right kind exist" + "pass") can be
satisfied by the **worker writing a new smoke test** rather than the repo's own tests
passing. This happened on the gazelle_cc tier-4 marks (F6: hiredis_test.c, unicode_test.cpp).
That's still a real signal that *the toolchain can compile+run a C++ test*, but it is NOT
"the project's existing suite passes." **Fix for phase 3:** judge should (a) prefer the
repo's existing test files (assert they were discovered, by name/count from the source
tree), and (b) tag any worker-authored-test pass distinctly from a native-suite pass. Until
then, read tier-4 with the per-experiment worker report, not the number alone.

### M2 — Disk is the binding operational constraint (25G VM)
The `repository_cache` accumulates every ecosystem's deps and ballooned to 7.7G of Go
modules in phase 1. Per-experiment `bazel clean --expunge` + clone deletion keeps output
bases flat, but the shared caches must be pruned between *ecosystem* shifts. Pre-phase-2
prune reclaimed 14G. Codify: prune `repository_cache`/`disk_cache` when changing language
families.


### FM1 — Bazel sandbox has no package-relative CWD ⇒ filesystem-assertion tests fail
testify `//assert:assert_test`: `TestFileExists/TestDirExists/TestNoFileExists/
TestNoDirExists` fail because they reference paths relative to the source package dir,
which `go test` provides but Bazel's sandbox does not. Not a Gazelle defect — a runtime
environment difference. Fixing properly needs runfiles/`data` wiring → *exceeds* "minor
edits" for those specific tests. (Other assert subtests `TestDidPanic/TestPanicsWithValue`
also failed — to be re-checked; possibly Go-version-sensitive.)

### FM2 — Go-version / runtime-sensitive tests
testify `//suite:suite_test`: `TestSuiteRecoverPanic`, `TestSuiteRequireTwice` fail under
the pinned SDK (panic-recovery + count assertions). Building on a newer Go than upstream
CI uses can shift behavior. Characterize per-repo; often a small `# gazelle:exclude` or a
test-arg fix, sometimes a genuine upstream/version issue.

> Takeaway shaping H-list: for clean Go libs the realistic ceiling on "Gazelle + minor
> edits" is **tier 3 plus most of tier 4**, with a small tail of environment-coupled
> tests (filesystem CWD, runfiles, Go-version drift) being the recurring blockers to a
> *clean* 100%.

## Recurring "minor edits" (candidates to templatize)

1. **Bump `go_sdk.download` to a recent stable Go** (not go.mod's minimum). — F2
2. **`bazel mod tidy`** after gazelle to fix `use_repo` rather than hand-listing deps. — F1
3. **`# gazelle:exclude <dir>`** for nested secondary `go.mod`s (tools/codegen/examples).
4. **`# gazelle:exclude`/`tags` for environment-coupled tests** (filesystem-CWD, network).

## Hypotheses (status)

- **H1 — CONFIRMED.** Flat Go libs reach tier 4 with the tiny seed + gazelle + mod tidy
  (echo/gin/bubbletea/fzf; even kratos-root despite codegen). Go is solved.
- **H2 — partially refuted.** Codegen did NOT block kratos (tier 4). The dominant *Go*
  blocker observed is **version skew** (F3), not cgo/embed/codegen. Re-scope to H2'.
- **H3 — supported.** flask needed a pinned lock (uv export) + manifest to reach tier 2;
  consistent with the prior, though the ceiling was build (2), not tests.
- **H4 — superseded by F5/F9.** The TS blocker isn't pnpm-vs-not; it's that the gazelle
  plugin's **native extractor won't build at all** (tier 0–1 regardless).
- **H5 — supported.** uv (huge Rust workspace) and microsoft/TypeScript (huge) scored
  lowest; size/complexity tracked failure better than stars.

### New hypotheses (phase 3)
- **H6.** `gazelle_cc` reaches tier 2–3 on most clean C/C++ *libraries* (no configure-time
  codegen), but needs `# keep`/`resolve` hand-tuning proportional to `#include "*.c"` and
  generated-header usage. _Prior: medium-high (2/2 so far)._
- **H7.** `rules_foreign_cc` reaches tier 2–3 on the majority of CMake/autotools projects
  with ≤5 edits; failures correlate with exotic configure steps / external system deps.
  _Prior: high (3/3 so far)._
- **H8.** `gazelle_rust` reaches tier ≥2 on *single-crate* / small workspaces but not on
  large multi-crate workspaces with proc-macros/build.rs. _Prior: medium._
