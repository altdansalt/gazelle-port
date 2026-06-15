#!/usr/bin/env bash
# ralph-loop.sh — the outer, deterministic loop.
#
# Usage:
#   bin/ralph-loop.sh [N]                 # run top-N candidates from data/candidates.json
#   REPOS="a/b c/d" bin/ralph-loop.sh     # run an explicit list
#
# For each repo: clone (cached) → EXPERIMENTER (Opus) proposes approaches →
# run-experiment.sh per approach (judge+worker+score). Appends a row to data/results.tsv.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OPUS=claude-opus-4-8
N="${1:-5}"

if [[ -n "${REPOS:-}" ]]; then
  mapfile -t LIST < <(printf '%s\n' $REPOS)
else
  mapfile -t LIST < <(jq -r ".[:$N][].full_name" data/candidates.json)
fi

RESULTS="$ROOT/data/results.tsv"
[[ -f "$RESULTS" ]] || echo -e "ts\trepo\tapproach\tlang\tscope\ttier\tpredicted\textra_files\tworker_exit" > "$RESULTS"

echo "#### ralph-loop over ${#LIST[@]} repos ####" >&2
for FULL in "${LIST[@]}"; do
  SLUG="${FULL//\//__}"
  CLONE="$ROOT/.cache/clones/$SLUG"
  echo; echo "########## $FULL ##########" >&2

  # clone (shared with run-experiment)
  if [[ ! -d "$CLONE/.git" ]]; then
    gh repo clone "$FULL" "$CLONE" -- --depth 1 >/dev/null 2>&1 \
      || git clone --depth 1 "https://github.com/$FULL" "$CLONE" >/dev/null 2>&1 \
      || { echo "!! clone failed, skipping" >&2; continue; }
  fi

  # gather context for the experimenter
  LS="$(cd "$CLONE" && git ls-files | head -500)"
  README="$(cd "$CLONE" && for f in README.md README.rst README readme.md; do [[ -f $f ]] && head -c 4000 "$f" && break; done)"
  META="$(jq -c --arg f "$FULL" '.[] | select(.full_name==$f)' data/candidates.json)"
  BCR="$(cat "$ROOT/data/bcr-versions.json")"

  EXPDIR="$ROOT/experiments/$SLUG"; mkdir -p "$EXPDIR"
  EXP_INPUT="$(jq -n --argjson meta "${META:-null}" --arg ls "$LS" --arg readme "$README" \
                 --argjson bcr "$BCR" \
                 '{repo_metadata:$meta, root_file_listing:$ls, readme_excerpt:$readme, bcr_versions:$bcr}')"

  echo ">> experimenter (Opus) proposing approaches ..." >&2
  {
    cat "$ROOT/prompts/experimenter.md"; echo; echo "## INPUT"; echo '```json'
    echo "$EXP_INPUT"; echo '```'
  } | "$ROOT/bin/llm.sh" "$OPUS" 8000 > "$EXPDIR/experimenter.raw" 2>"$EXPDIR/experimenter.usage" || true
  "$ROOT/bin/json-extract.sh" < "$EXPDIR/experimenter.raw" > "$EXPDIR/approaches.json" || true

  if ! jq -e '.approaches' "$EXPDIR/approaches.json" >/dev/null 2>&1; then
    echo "!! experimenter produced no approaches; skipping $FULL" >&2; continue
  fi
  napp=$(jq '.approaches|length' "$EXPDIR/approaches.json")
  echo "   approaches: $napp ($(jq -r '[.approaches[].id]|join(", ")' "$EXPDIR/approaches.json"))" >&2

  for ((a=0; a<napp; a++)); do
    AJSON="$EXPDIR/.approach-$a.json"
    jq -c ".approaches[$a]" "$EXPDIR/approaches.json" > "$AJSON"
    "$ROOT/bin/run-experiment.sh" "$FULL" "$AJSON" || echo "!! experiment errored (continuing)" >&2
    R="$EXPDIR/$(jq -r '.id' "$AJSON")/result.json"
    if [[ -f "$R" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(jq -r .scope "$AJSON" >/dev/null 2>&1; date -u +%FT%TZ 2>/dev/null || echo now)" \
        "$FULL" "$(jq -r .id "$AJSON")" "$(jq -r .language "$AJSON")" \
        "$(jq -r '.scope // "//..."' "$AJSON")" \
        "$(jq -r '.tier_reached' "$R")" "$(jq -r '.predicted_tier // "?"' "$R")" \
        "$(jq -r '.extra_edited_files // "?"' "$R")" "$(jq -r '.worker_exit // "?"' "$R")" \
        >> "$RESULTS"
    fi
  done
done
echo; echo "#### done. summary: data/results.tsv ####" >&2
column -t -s$'\t' "$RESULTS" >&2 || cat "$RESULTS" >&2
