# Findings

Rolling, evidence-backed record. Each finding cites the experiment(s) that produced it.
Hypotheses live at the bottom until confirmed/refuted.

## Summary scoreboard

| Language | Experiments | Best tier | Notes |
|----------|-------------|-----------|-------|
| **Go**   | 7 (Strategy A) | **4** (5 of 6 repos) | echo/gin/bubbletea/fzf/kratos → tier 4; testify → 3 (F3 version skew). Go is *solved*. |
| **Python** | 1 (Strategy A) | **2** | flask: library builds via rules_python + gazelle; needs lock+manifest+resolve (F4). |
| **TS/JS** | 1 (Strategy A) | **1** | zustand: the gazelle plugin's own native extractor won't build (F5). |
| Rust / C / C++ | 0 | – | phase 2 (gazelle_rust / gazelle_cc / rules_foreign_cc) |
| Proto    | 0           | –         | (kratos has proto subdirs; not isolated yet) |

Tiers: 0 nothing · 1 deps/gazelle run · 2 `//...` builds · 3 tests discovered · 4 tests pass.

> **Headline so far:** Gazelle's per-ecosystem maturity is starkly tiered. Go reaches a
> clean tier 4 with ~5–15 line seeds. Python reaches tier 2 (build) but full test wiring
> exceeds "minor edits". TS can't even *run* the generator today (native-build hurdle).
> This directly answers "what's achievable now": **Go ≫ Python > TS**, with Rust/C/C++ and
> foreign_cc under test in phase 2.

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

## Failure modes observed

### FM3 — Harness bug (FIXED): `git ls-files | head -N` SIGPIPE under `pipefail`
Lost 2 experiments (gitleaks, kratos's 2nd approach): `head` closes the pipe at N lines,
`git` gets SIGPIPE (141), `pipefail` propagates it, `set -e` aborts the experiment. Racy
(buffering-dependent) so it hit only repos with >N files, intermittently. Fixed by
`|| true` on the substitution in `run-experiment.sh` and `ralph-loop.sh`. *Lesson logged
because the loop must be deterministic; a flaky truncation silently dropped results.*


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
