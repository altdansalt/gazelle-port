#!/usr/bin/env bash
# select-repos.sh — build the scored candidate dataset (ADR-004, docs/04).
#
# Pulls popular+active repos per target language via `gh api`, enriches each with a
# root-tree probe (build-system detection, manifest presence), drops repos that already
# use Bazel / are archived/forks/docs, scores by Gazelle-amenability + activity, and
# writes data/candidates.json (+ .md).
#
# Env: PUSHED_SINCE (default 2026-03-01), RAW_PER_LANG (default 80).
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE=.cache/select; mkdir -p "$CACHE" data
PUSHED_SINCE="${PUSHED_SINCE:-2026-03-01}"
RAW_PER_LANG="${RAW_PER_LANG:-80}"

# language : min-stars : language-prior (0..1)  — see docs/03 tiers.
LANGS=( "Go:2000:1.00" "Python:20000:0.65" "TypeScript:20000:0.45" "Java:10000:0.30" )

############################################
# phase 1: search
############################################
echo ">> phase 1: search (pushed:>$PUSHED_SINCE, top $RAW_PER_LANG/lang)" >&2
: > "$CACHE/raw.ndjson"
for entry in "${LANGS[@]}"; do
  IFS=: read -r lang minstars prior <<<"$entry"
  echo "   - $lang (stars:>$minstars) ..." >&2
  pages=$(( (RAW_PER_LANG + 99) / 100 ))
  for ((p=1; p<=pages; p++)); do
    gh api -X GET search/repositories \
      -f q="language:$lang stars:>$minstars pushed:>$PUSHED_SINCE" \
      -f sort=stars -f order=desc -f per_page=100 -f page="$p" \
      --jq ".items[] | {full_name, language, stars:.stargazers_count, forks:.forks_count,
            open_issues:.open_issues_count, pushed_at, size, default_branch,
            archived, fork, topics, lang_prior:$prior, search_lang:\"$lang\"}" \
      >> "$CACHE/raw.ndjson" 2>>"$CACHE/search.err" \
      || { echo "     (search hiccup p$p; sleeping 20s)" >&2; sleep 20; }
    sleep 2   # stay under the 30/min search budget
  done
done
jq -s 'unique_by(.full_name)' "$CACHE/raw.ndjson" > "$CACHE/uniq.json"
echo "   raw unique: $(jq length "$CACHE/uniq.json")" >&2

############################################
# phase 2: enrich (root-tree probe, 1 core call/repo) + filter
############################################
echo ">> phase 2: enrich + filter" >&2
: > "$CACHE/enriched.ndjson"
total=$(jq length "$CACHE/uniq.json"); i=0
while IFS= read -r repo; do
  i=$((i+1))
  full=$(jq -r .full_name <<<"$repo")
  branch=$(jq -r .default_branch <<<"$repo")
  tcache="$CACHE/tree-${full//\//_}.json"
  if [[ ! -s "$tcache" ]]; then
    gh api "repos/$full/git/trees/$branch" --jq '[.tree[].path]' \
      > "$tcache" 2>>"$CACHE/tree.err" || echo '[]' > "$tcache"
  fi
  files="$(cat "$tcache")"
  printf '%s/%s ' "$i" "$total" >&2
  jq -c --argjson files "$files" '
    . + ($files | {
      files_root: .,
      is_bazel:   (any(.[]; test("^(MODULE\\.bazel|WORKSPACE(\\.bazel)?|WORKSPACE\\.bzlmod)$"))),
      has_go_mod: (any(.[]; .=="go.mod")),
      has_pyproj: (any(.[]; .=="pyproject.toml" or .=="setup.py" or .=="requirements.txt")),
      has_pkgjson:(any(.[]; .=="package.json")),
      has_pnpm:   (any(.[]; .=="pnpm-lock.yaml")),
      has_pom:    (any(.[]; .=="pom.xml" or .=="build.gradle" or .=="build.gradle.kts")),
      has_proto:  (any(.[]; test("\\.proto$"))),
    }) | del(.files_root)
  ' <<<"$repo" >> "$CACHE/enriched.ndjson"
done < <(jq -c '.[]' "$CACHE/uniq.json")
echo >&2

############################################
# phase 3: filter + score + write
############################################
echo ">> phase 3: score + write data/candidates.json" >&2
DOC_TOPICS='["awesome","books","book","tutorial","tutorials","roadmap","cheatsheet","interview","free-programming-books","list","awesome-list","resources","course","learning"]'

jq -s --argjson doc "$DOC_TOPICS" --arg since "$PUSHED_SINCE" '
  # days since pushed, using only the YYYY-MM-DD prefix (no host date dep needed for ranking:
  # recency proxy = lexical pushed_at; newer string sorts later)
  map(
    # manifest-at-root presence for the search language
    (.has_manifest =
       (if .search_lang=="Go" then .has_go_mod
        elif .search_lang=="Python" then .has_pyproj
        elif .search_lang=="TypeScript" then .has_pkgjson
        elif .search_lang=="Java" then .has_pom
        else false end))
    | (.is_doc = ((.topics // []) | any(. as $t | $doc | index($t))))
    # simplicity proxy: smaller repos score higher (size in KB); clamp
    | (.simplicity = (1 - ((.size // 0) / 500000) | if . < 0 then 0 else . end))
    # activity proxy: recent push (lexical) + open issue volume (capped)
    | (.activity = ( (.pushed_at[0:10]) as $d
                     | (if $d > "2026-05-15" then 1.0
                        elif $d > "2026-04-15" then 0.8
                        elif $d > "2026-03-15" then 0.6 else 0.4 end) ))
    | (.risk = ( (if .size > 200000 then 0.4 else 0 end)
                 + (if .has_proto then 0.1 else 0 end) ))
    | (.score = ( 0.50*.lang_prior + 0.25*.activity + 0.15*.simplicity
                  + (if .has_manifest then 0.10 else 0 end) - 0.20*.risk ))
  )
  # FILTER: drop already-bazel, archived, forks, docs, no-manifest
  | map(select(.is_bazel|not))
  | map(select(.archived|not))
  | map(select(.fork|not))
  | map(select(.is_doc|not))
  | map(select(.has_manifest))
  | sort_by(-.score)
' "$CACHE/enriched.ndjson" > data/candidates.json

n=$(jq length data/candidates.json)
echo "   candidates: $n" >&2

############################################
# phase 4: human-readable top slice
############################################
{
  echo "# Candidate repos (generated by bin/select-repos.sh)"
  echo
  echo "_pushed since $PUSHED_SINCE; already-Bazel / archived / forks / docs / no-root-manifest excluded._"
  echo "_$n candidates. Scoring: see docs/04. Tiers/priors: see docs/03._"
  echo
  echo "| # | repo | lang | stars | size(KB) | pushed | manifest | proto | score |"
  echo "|---|------|------|-------|----------|--------|----------|-------|-------|"
  jq -r 'to_entries[] | select(.key < 60) | .value as $v | .key as $k |
    "| \($k+1) | [\($v.full_name)](https://github.com/\($v.full_name)) | \($v.search_lang) | \($v.stars) | \($v.size) | \($v.pushed_at[0:10]) | \(if $v.has_go_mod then "go.mod" elif $v.has_pyproj then "py" elif $v.has_pkgjson then (if $v.has_pnpm then "pkg+pnpm" else "pkg" end) elif $v.has_pom then "jvm" else "?" end) | \(if $v.has_proto then "yes" else "" end) | \($v.score*100|floor/100) |"' \
    data/candidates.json
} > data/candidates.md

echo ">> done. data/candidates.json ($n) + data/candidates.md" >&2
