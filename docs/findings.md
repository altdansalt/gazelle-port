# Findings

Rolling, evidence-backed record. Each finding cites the experiment(s) that produced it.
Hypotheses live at the bottom until confirmed/refuted.

## Summary scoreboard

| Language | Experiments | Best tier reached | Notes |
|----------|-------------|-------------------|-------|
| Go       | 1 (manual)  | 3 (build 100%, 6/8 test targets) | stretchr/testify |
| Python   | 0           | –                 | pending |
| TS/JS    | 0           | –                 | pending |
| Proto    | 0           | –                 | pending |

Tiers: 0 nothing · 1 deps/gazelle run · 2 `//...` builds · 3 tests discovered · 4 tests pass.

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

## Failure modes observed

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
