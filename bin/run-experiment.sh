#!/usr/bin/env bash
# run-experiment.sh — run ONE experiment (one approach) end to end.
#
# Usage: bin/run-experiment.sh <full_name> <approach.json> [--fresh]
#
# Steps: shallow-clone (cached) → worktree on exp/<id> → seed MODULE.bazel/BUILD/.bazelrc
# → JUDGE (Opus) writes EXPECTATIONS.json → WORKER (Sonnet, claude CLI) edits to satisfy
# them → harness scores independently → save diff + trace + result.json.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

FULL="${1:?full_name}"; APPROACH="${2:?approach.json}"; FRESH="${3:-}"
SLUG="${FULL//\//__}"
AID="$(jq -r '.id' "$APPROACH")"
SCOPE="$(jq -r '.scope // "//..."' "$APPROACH")"
BRANCH_DEFAULT="$(jq -r '.default_branch // "main"' "$APPROACH" 2>/dev/null || echo main)"

EXPDIR="$ROOT/experiments/$SLUG/$AID"
TRACEDIR="$ROOT/traces/$SLUG/$AID"
CLONE="$ROOT/.cache/clones/$SLUG"
WT="$ROOT/.cache/worktrees/${SLUG}__${AID}"

OPUS=claude-opus-4-8
GW="${LLM_GATEWAY:-http://169.254.169.254/gateway/llm/anthropic}"
WORKER_MODEL="${WORKER_MODEL:-claude-sonnet-4-6}"
WORKER_TURNS="${WORKER_TURNS:-50}"
WORKER_TIMEOUT="${WORKER_TIMEOUT:-2400}"   # 40 min wall-clock cap
BAZEL_TIMEOUT="${BAZEL_TIMEOUT:-1200}"

[[ "$FRESH" == "--fresh" ]] && { git -C "$CLONE" worktree remove --force "$WT" 2>/dev/null || true; rm -rf "$EXPDIR" "$WT"; }
mkdir -p "$EXPDIR" "$TRACEDIR"

echo "════ experiment $FULL / $AID  (scope $SCOPE) ════" >&2

############################################
# 1. clone (cached, shallow) + worktree
############################################
if [[ ! -d "$CLONE/.git" ]]; then
  echo ">> cloning $FULL (shallow) ..." >&2
  gh repo clone "$FULL" "$CLONE" -- --depth 1 >/dev/null 2>&1 \
    || git clone --depth 1 "https://github.com/$FULL" "$CLONE" >/dev/null 2>&1
fi
git -C "$CLONE" worktree remove --force "$WT" 2>/dev/null || true
rm -rf "$WT"
git -C "$CLONE" worktree add -f -b "exp/$AID" "$WT" >/dev/null 2>&1 \
  || git -C "$CLONE" worktree add -f --detach "$WT" >/dev/null 2>&1

############################################
# 2. seed Bazel files from the approach
############################################
jq -r '.module_bazel' "$APPROACH" > "$WT/MODULE.bazel"
# don't clobber an existing root BUILD; gazelle path expects BUILD.bazel
jq -r '.root_build' "$APPROACH" > "$WT/BUILD.bazel"
jq -r '.bazelrc // ""' "$APPROACH" > "$WT/.bazelrc"
# shared caches to speed repeated experiments + keep network fetches once
{ echo "common --disk_cache=$ROOT/.cache/bazel-disk"
  echo "common --repository_cache=$ROOT/.cache/bazel-repo"
  echo "common --noshow_progress"
  echo "test --test_output=errors"; } >> "$WT/.bazelrc"
cp "$APPROACH" "$EXPDIR/approach.json"

############################################
# 3. JUDGE → EXPECTATIONS.json  (Opus, one-shot)
############################################
echo ">> judge (Opus) writing expectations ..." >&2
ROOTLS="$(cd "$WT" && git ls-files | head -400)"
JUDGE_INPUT="$(jq -n --arg full "$FULL" --arg scope "$SCOPE" \
  --argjson approach "$(cat "$APPROACH")" --arg ls "$ROOTLS" \
  '{repo:$full, scope:$scope, approach:$approach, file_listing:$ls}')"
{
  cat "$ROOT/prompts/judge.md"; echo; echo "## INPUT"; echo '```json'; echo "$JUDGE_INPUT"; echo '```'
} | "$ROOT/bin/llm.sh" "$OPUS" 4000 > "$TRACEDIR/judge.raw" 2>"$TRACEDIR/judge.usage" || true
"$ROOT/bin/json-extract.sh" < "$TRACEDIR/judge.raw" > "$EXPDIR/expectations.json" || true
if ! jq -e '.expectations' "$EXPDIR/expectations.json" >/dev/null 2>&1; then
  echo "!! judge produced no valid expectations; using default ladder" >&2
  jq -n --arg full "$FULL" --arg aid "$AID" --arg scope "$SCOPE" '{repo:$full,approach_id:$aid,scope:$scope,
    expectations:[
      {id:"modgraph",tier:1,cmd:"bazel mod graph",expect:{exit:0}},
      {id:"gazelle",tier:1,cmd:"bazel run //:gazelle",expect:{exit:0}},
      {id:"build",tier:2,cmd:("bazel build "+$scope),expect:{exit:0}},
      {id:"test",tier:4,cmd:("bazel test "+$scope),expect:{exit:0}}
    ]}' > "$EXPDIR/expectations.json"
fi
cp "$EXPDIR/expectations.json" "$WT/EXPECTATIONS.json"

############################################
# 4. WORKER (Sonnet via claude CLI) inside the worktree
############################################
echo ">> worker (Sonnet) iterating (max ${WORKER_TURNS} turns / ${WORKER_TIMEOUT}s) ..." >&2
WORKER_PROMPT="$(cat "$ROOT/prompts/worker.md")
\nYour worktree is the current directory. EXPECTATIONS.json is present. Begin."
set +e
( cd "$WT" && \
  ANTHROPIC_BASE_URL="$GW" ANTHROPIC_API_KEY=implicit ANTHROPIC_MODEL="$WORKER_MODEL" \
  timeout "$WORKER_TIMEOUT" claude -p "$WORKER_PROMPT" \
    --model "$WORKER_MODEL" \
    --dangerously-skip-permissions \
    --output-format stream-json --verbose \
) > "$TRACEDIR/worker.stream.jsonl" 2>"$TRACEDIR/worker.err"
WCODE=$?
set -e
# distill final assistant text from the stream
jq -rs 'map(select(.type=="result")) | last | .result // ""' \
  "$TRACEDIR/worker.stream.jsonl" 2>/dev/null > "$EXPDIR/worker-report.txt" || true
echo "   worker exit $WCODE (turns/tokens in trace)" >&2

############################################
# 5. score (harness, independent) + capture diff
############################################
echo ">> scoring ..." >&2
"$ROOT/bin/score.sh" "$WT" "$EXPDIR/expectations.json" "$EXPDIR/result.json" "$BAZEL_TIMEOUT" || true
# worker diff vs the seeded state: diff against the original clone HEAD
( cd "$WT" && git add -A && git diff --cached --stat > "$EXPDIR/worker.diffstat" 2>/dev/null || true
  git diff --cached > "$EXPDIR/worker.diff" 2>/dev/null || true )

# enrich result.json with metadata
TIER=$(jq -r '.tier_reached' "$EXPDIR/result.json" 2>/dev/null || echo 0)
PRED=$(jq -r '.predicted_tier // empty' "$APPROACH")
EDIT_FILES=$(cd "$WT" && git diff --cached --name-only | grep -vE '^(MODULE\.bazel|BUILD\.bazel|\.bazelrc|EXPECTATIONS\.json|MODULE\.bazel\.lock)$' | wc -l | tr -d ' ')
jq --arg repo "$FULL" --arg aid "$AID" --arg scope "$SCOPE" --argjson pred "${PRED:-null}" \
   --argjson editfiles "$EDIT_FILES" --argjson wcode "$WCODE" \
   '. + {repo:$repo, approach_id:$aid, scope:$scope, predicted_tier:$pred,
         extra_edited_files:$editfiles, worker_exit:$wcode}' \
   "$EXPDIR/result.json" > "$EXPDIR/result.json.tmp" && mv "$EXPDIR/result.json.tmp" "$EXPDIR/result.json"

echo "════ $FULL / $AID → tier $TIER (predicted ${PRED:-?}, extra files edited $EDIT_FILES) ════" >&2

# DISK HYGIENE (critical: 25G disk). Reclaim this workspace's output base — build
# outputs are disposable now that we've scored + captured the diff. The shared
# repository_cache / disk_cache (under .cache/) persist to speed later repos.
( cd "$WT" && bazel clean --expunge >/dev/null 2>&1 ) || true
# tidy: drop the heavy worktree, keep records
git -C "$CLONE" worktree remove --force "$WT" 2>/dev/null || true
rm -rf "$WT" 2>/dev/null || true
# drop the shallow clone too (re-cloned on demand; keeps disk flat across a big batch)
[[ "${KEEP_CLONES:-0}" == "1" ]] || rm -rf "$CLONE" 2>/dev/null || true
df -h /home 2>/dev/null | tail -1 | awk '{print "   disk free: "$4" ("$5" used)"}' >&2
