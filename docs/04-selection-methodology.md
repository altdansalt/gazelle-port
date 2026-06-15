# Candidate selection methodology

## Source

Equivalent of top1000repos.com (popular GitHub repos), reconstructed via `gh api`
(ADR-004). We run **targeted, per-language searches** for popular *and* active repos
rather than filtering the generic top-by-stars list, because the latter is dominated by
awesome-lists, books, and docs that aren't buildable code.

## Pull

For each target language L in {Go, Python, TypeScript, C++, Java, Rust*}:
```
gh api -X GET search/repositories \
  -f q="language:L stars:>N pushed:>YYYY-MM-DD sort:stars" -f per_page=100 …
```
- `pushed:>` enforces recency (active). `stars:>N` enforces popularity.
- (*Rust has no first-party Gazelle plugin; included only as a contrast/negative class.)

Captured per repo: `full_name, language, stargazers_count, forks, open_issues,
pushed_at, size, default_branch, topics, archived, fork`.

## Enrich & filter

Per repo, one cheap signal pass (root tree via `git/trees/{branch}` or contents API):
- **Build-system detection** — presence of `MODULE.bazel`/`WORKSPACE*` ⇒ **drop**
  (already Bazel). Note existing system (go.mod, package.json, pyproject, CMake, Maven…).
- **Buildability signal** — has the language's manifest at root (go.mod / pyproject /
  package.json …) and at least one source/test dir.
- **Activity** — recent `pushed_at`; high open-PR volume (via `search/issues type:pr`).
- **Exclusions** — `archived`, `fork`, pure-doc topics (`awesome`, `books`, `tutorial`),
  and outsized monorepos (`size` above a cap) unless we deliberately probe a slice.

## Score

`score = w_lang·langPrior + w_active·activity + w_simple·simplicityProxy − w_risk·risk`

- `langPrior` from `docs/03` tiers (Go highest).
- `activity` = normalized recent pushes / open-PR count / commit cadence.
- `simplicityProxy` = smaller size, has go.mod-at-root / flat layout, has tests.
- `risk` = monorepo size, heavy code-gen topics, cgo/native hints.

Output: `data/candidates.json` (full, scored, sorted) + `data/candidates.md` (top slice,
human-readable, with the chosen Gazelle hypothesis per repo).

## What the loop consumes

The loop reads the top of `data/candidates.json` as its work queue. Each repo flows into
the Experimenter (which may fan out multiple approaches per repo).
