# Ruleset & Gazelle-plugin catalog

**Source of truth:** `buildreg.exe.xyz/index.json` (a fast index of the Bazel Central
Registry; 1164 modules as of 2026-06-15). We snapshot it to `.cache/buildreg/index.json`
and extract plugin/ruleset names + latest versions into `data/bcr-versions.json`.
Re-pull with `curl -sS https://buildreg.exe.xyz/index.json`.

This replaces "from memory" guessing (ADR-006). Two distinct strategies for porting a
non-Bazel repo, with very different deliverables:

## Strategy A — Gazelle (source-native BUILD generation)

Gazelle reads source and emits a **fine-grained** Bazel target graph. Best outcome: a
real Bazel-native build. Maturity varies enormously by language.

| Language | Plugin (BCR module) | ★ | Maturity | Notes |
|----------|---------------------|---|----------|-------|
| **Go** | `gazelle` (native) | 1395 | **Production** | Tier-4 routine (see findings). |
| **Protobuf** | `gazelle` (native) | 1395 | **Production** | proto_library/go_proto. |
| Protobuf/gRPC (poly) | `build_stack_rules_proto` | 284 | Solid | multi-lang proto/grpc gazelle. |
| **Python** | `rules_python_gazelle_plugin` | 677 | **Production** | needs pip lock + manifest. |
| **JS/TS** | `aspect_gazelle_js` (aspect-build/aspect-gazelle) | 13 | Active (135 commits/90d) | best-maintained non-Go/Py gazelle; pairs with `aspect_rules_js`/`_ts`. |
| JS/TS (alt) | `gazelle_ts` (hermeticbuild) | 7 | Emerging | Rust import-extractor via cgo. |
| Node (alt) | `com_github_benchsci_rules_nodejs_gazelle` | 22 | Niche | rules_nodejs flavor. |
| **Rust** | `gazelle_rust` (Calsign) | 49 | **Emerging** | reads Cargo.toml + `use` graph; pairs w/ `rules_rust` crate_universe. **The lever for cargo repos.** |
| **C/C++** | `gazelle_cc` (EngFlow) | 42 | **Emerging** | source-native cc_library/cc_binary from #includes. Alternative to foreign_cc. |
| Swift | `swift_gazelle_plugin` (cgrindel) | 10 | Experimental (active) | pairs w/ `rules_swift_package_manager`. |
| Haskell | `gazelle_cabal` (tweag) | 14 | Experimental | from .cabal files; + `gazelle_haskell_modules`. |
| Scala | `build_stack_scala_gazelle` (stackb) | 15 | Experimental | |
| D | `gazelle_d` | 0 | Toy | |

## Strategy B — Foreign-build wrapping (NOT Gazelle)

For projects whose build system Gazelle can't model (CMake/Make/autotools/Meson/Ninja),
Bazel can **invoke the project's own build** as a build action. Deliverable is **coarse**:
one target wrapping the foreign build's outputs — Bazel-*consumable*, not Bazel-*native*.
No fine-grained graph, no per-file incrementality, but "most of the work" for free.

| Ruleset | ★ | Covers | For (from your lists) |
|---------|---|--------|-----------------------|
| **`rules_foreign_cc`** v0.15.1 | 732 | CMake, configure-make, GNU Make, Meson, Ninja, boost | redis (make), llama.cpp (cmake), neovim (cmake), clickhouse (cmake), vim (qmake→make), julia (make), cpython (make) |
| `rules_cc_autoconf` / `rules_autoconf` | 5 / 2 | autoconf-style configure | autotools projects |
| `rules_zig` v0.16.0 | 75 | Zig (native rules, **no gazelle**) | ghostty, zig — hand-write BUILD |
| `rules_rust` v0.70.0 | 813 | Rust core + `crate_universe` (Cargo deps) | all cargo repos (BUILD via `gazelle_rust`) |
| `rules_dotnet` / `rules_swift_package_manager` / `rules_haskell` / `rules_kotlin` / `rules_ruby` / `rules_perl` / `rules_d` | — | their langs | — |

**No realistic Bazel path:** `gn` (nodejs/node — Chromium's generator), `msbuild`-only
Windows builds. Document as out-of-scope negatives.

## What this means for our research question

- **Gazelle, today:** a *production* answer for Go / proto / Python; a *credible* answer
  for JS/TS (Aspect); an *emerging, worth-probing* answer for Rust and C/C++; and
  *experimental* for Swift/Haskell/Scala. The honest frontier is Rust + C/C++.
- **rules_foreign_cc:** changes the question for the CMake/Make giants. It can almost
  certainly produce a building Bazel target for redis/llama.cpp/etc. with minor edits —
  but that's a *different, coarser* artifact than a Gazelle port. We test both and report
  which deliverable each repo class admits.

See ADR-006 (buildreg as source) and the phase-2 experiment plan in `docs/07-phase2-plan.md`.
