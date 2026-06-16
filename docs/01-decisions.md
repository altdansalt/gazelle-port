# Decision log

ADR-style. Newest decisions appended. Each: context → decision → why.

## ADR-001: LLM access via the exe.dev gateway metadata IP

**Context.** exe.dev documents a managed LLM gateway. The documented integration
hostname `https://llm.int.exe.xyz` returns `403 integration not found or not attached to
this VM` on this VM. The low-level metadata endpoint works.

**Decision.** All agents call:
`http://169.254.169.254/gateway/llm/anthropic/v1/messages` (Anthropic Messages API,
header `anthropic-version: 2023-06-01`, no API key — the VM is authenticated).
For the `claude` CLI: `ANTHROPIC_BASE_URL=http://169.254.169.254/gateway/llm/anthropic`,
`ANTHROPIC_API_KEY=implicit` (placeholder).

**Why.** It's the working endpoint here. Verified: `claude-opus-4-8` and
`claude-sonnet-4-6` both return 200; `claude -p` runs headless against it.

## ADR-002: Models per role

**Decision.** Experimenter = `claude-opus-4-8`. Judge = `claude-opus-4-8`. Worker =
`claude-sonnet-4-6`. **Why.** Per project brief; Opus for the planning/grading judgment,
Sonnet for the cheaper high-volume edit-and-iterate worker.

## ADR-003: "Use Bazel for everything" scoped to the experiments

**Context.** Brief says "Use Bazel for everything. Do not rely on the host system
(outside git and gh for cloning)."

**Decision.** Interpreted as: **the experiments under test must build/test hermetically
under Bazel** (toolchains from Bazel, not host Go/Python/Node). The deterministic
orchestration glue may use the blessed host primitives: `git`, `gh`, `bash`, `curl`,
`bazel`, and the `claude` CLI.

**Why.** A Ralph loop is by nature a dumb deterministic shell harness wrapping smart LLM
calls; forcing the glue itself through Bazel adds friction without serving the goal. The
*scientific object* — the port — is what must be Bazel-hermetic, and it is.

## ADR-004: Reconstruct the candidate set from the GitHub API, not by scraping

**Context.** top1000repos.com is a client-side SvelteKit app that itself calls the public
GitHub API (`/search`, `/repos/{r}`, `/languages`, git trees); it has no data export.

**Decision.** Reconstruct an equivalent-or-better dataset directly via `gh api`
(blessed), enriching with the exact signals we need (language, recent push activity,
build-system detection, open-PR volume). Honor the spirit of "top1000repos" = popular
active repos, but rank by Gazelle-amenability + activity rather than raw stars.

**Why.** More reliable, gives the metrics selection actually needs, no brittle scraping.

## ADR-005: Worktree-per-experiment isolation

**Decision.** Each experiment is a `git worktree` of a shallow clone of the target repo,
on its own branch. The worker only edits inside its worktree. We capture the full diff
and the agent trace per experiment.

**Why.** Cheap isolation, parallel-safe, trivially diffable, easy to discard/retry —
exactly the Ralph loop's "throwaway attempt" unit.

## ADR-006: buildreg.exe.xyz is the source for the ruleset/plugin universe

**Context.** Initial Gazelle-plugin knowledge was from memory (Go/proto/python/js) —
too narrow. Project owner asked to exercise more than Go and pointed at
`buildreg.exe.xyz` (an indexed view of the Bazel Central Registry, 1164 modules).

**Decision.** Enumerate Gazelle plugins *and* foreign-build/language rulesets from
`buildreg.exe.xyz/index.json` (snapshot in `.cache/buildreg/`), distilled into
`docs/06-ruleset-catalog.md` + `data/bcr-versions.json`. The experimenter is fed this
catalog so it picks a real, resolvable ruleset per language instead of guessing.

**Why.** Authoritative, versioned, current. Surfaced the non-obvious levers:
`gazelle_rust`, `gazelle_cc` (source-native C/C++!), `aspect_gazelle_js`, and the
foreign-build path via `rules_foreign_cc`.

## ADR-007: Two deliverable classes, scored separately

**Context.** "Can a ruleset do most of the work?" — yes, but *which kind of result*?

**Decision.** Distinguish **Strategy A (Gazelle, source-native, fine-grained Bazel graph)**
from **Strategy B (rules_foreign_cc et al., wrap the project's own build, coarse target)**.
Both count as "a working Bazel build+test," but we tag each experiment with its strategy
and report them separately — a foreign_cc wrap of redis is a real but *different* win than
a Gazelle port of a Go lib. **Why.** Honest answer to the research question needs the
distinction; conflating them would overstate Gazelle's reach.
