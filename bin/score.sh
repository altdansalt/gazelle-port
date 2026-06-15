#!/usr/bin/env bash
# score.sh — deterministically run an experiment's expectations and emit result.json.
#
# Usage: bin/score.sh <worktree> <expectations.json> <result.json> [cmd_timeout_secs]
#
# Runs each expectation's cmd in the worktree, evaluates its `expect` predicate, and
# records pass/fail + the tier reached. The Worker never runs this — the harness does.
set -euo pipefail

WT="${1:?worktree}"; EXP="${2:?expectations.json}"; OUT="${3:?result.json}"
TO="${4:-900}"
WT="$(cd "$WT" && pwd)"
LOGDIR="$(dirname "$OUT")/expectation-logs"; mkdir -p "$LOGDIR"

results='[]'; tier_reached=0; ladder_intact=1; n=$(jq '.expectations|length' "$EXP")

for ((i=0; i<n; i++)); do
  e=$(jq -c ".expectations[$i]" "$EXP")
  id=$(jq -r '.id' <<<"$e"); tier=$(jq -r '.tier // 0' <<<"$e")
  cmd=$(jq -r '.cmd' <<<"$e")
  allow_nonzero=$(jq -r '.expect.allow_nonzero // false' <<<"$e")
  exp_exit=$(jq -r '.expect.exit // 0' <<<"$e")
  min_lines=$(jq -r '.expect.stdout_min_lines // empty' <<<"$e")
  out_re=$(jq -r '.expect.stdout_regex // empty' <<<"$e")
  err_re=$(jq -r '.expect.stderr_regex // empty' <<<"$e")

  o="$LOGDIR/$id.out"; r="$LOGDIR/$id.err"
  echo "  [$((i+1))/$n] tier$tier $id: $cmd" >&2
  set +e
  ( cd "$WT" && timeout "$TO" bash -lc "$cmd" ) >"$o" 2>"$r"; code=$?
  set -e

  pass=1; reason=""
  if [[ "$allow_nonzero" != "true" ]]; then
    [[ "$code" -eq "$exp_exit" ]] || { pass=0; reason="exit $code != $exp_exit"; }
  fi
  if [[ -n "$min_lines" && $pass -eq 1 ]]; then
    got=$(grep -cve '^[[:space:]]*$' "$o" || true)
    [[ "$got" -ge "$min_lines" ]] || { pass=0; reason="stdout lines $got < $min_lines"; }
  fi
  if [[ -n "$out_re" && $pass -eq 1 ]]; then
    grep -qE "$out_re" "$o" || { pass=0; reason="stdout !~ /$out_re/"; }
  fi
  if [[ -n "$err_re" && $pass -eq 1 ]]; then
    grep -qE "$err_re" "$r" || { pass=0; reason="stderr !~ /$err_re/"; }
  fi

  if [[ "$allow_nonzero" == "true" ]]; then
    : # informational; does not affect ladder
  elif [[ $pass -eq 1 && $ladder_intact -eq 1 ]]; then
    (( tier > tier_reached )) && tier_reached=$tier
  elif [[ $pass -eq 0 ]]; then
    ladder_intact=0
  fi

  results=$(jq -c --arg id "$id" --argjson tier "$tier" --arg cmd "$cmd" \
    --argjson code "$code" --argjson pass "$pass" --arg reason "$reason" \
    '. + [{id:$id,tier:$tier,cmd:$cmd,exit:$code,pass:($pass==1),reason:$reason}]' \
    <<<"$results")
done

jq -n --argjson r "$results" --argjson tier "$tier_reached" \
  '{tier_reached:$tier, expectations:$r,
    passed:( $r | map(select(.pass)) | length ),
    total:( $r | length )}' > "$OUT"
echo ">> tier reached: $tier_reached  ($(jq -r '"\(.passed)/\(.total) checks"' "$OUT"))" >&2
