#!/usr/bin/env bash
# rollup.sh — aggregate experiments/*/*/result.json into a scoreboard.
# Prints a per-experiment table + per-language tier summary to stdout.
set -euo pipefail
cd "$(dirname "$0")/.."

shopt -s nullglob
results=(experiments/*/*/result.json)
if [[ ${#results[@]} -eq 0 ]]; then echo "no results yet"; exit 0; fi

echo "## Per-experiment results"
echo
printf "| repo | approach | scope | tier | predicted | checks | extra-files | worker-exit |\n"
printf "|------|----------|-------|------|-----------|--------|-------------|-------------|\n"
for r in "${results[@]}"; do
  jq -r '"| \(.repo) | \(.approach_id) | \(.scope) | **\(.tier_reached)** | \(.predicted_tier // "?") | \(.passed)/\(.total) | \(.extra_edited_files // "?") | \(.worker_exit // "?") |"' "$r"
done | sort

echo
echo "## Tier reached, by language"
echo
# join language from approach.json
for r in "${results[@]}"; do
  d=$(dirname "$r"); lang=$(jq -r '.language // "?"' "$d/approach.json" 2>/dev/null)
  tier=$(jq -r '.tier_reached' "$r")
  echo -e "$lang\t$tier"
done | sort | awk -F'\t' '
  {n[$1]++; if($2>max[$1])max[$1]=$2; sum[$1]+=$2}
  END{ printf "| lang | n | best tier | mean tier |\n|---|---|---|---|\n";
       for(l in n) printf "| %s | %d | %d | %.1f |\n", l, n[l], max[l], sum[l]/n[l] }'
