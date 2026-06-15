#!/usr/bin/env bash
# llm.sh — one-shot call to the exe.dev Anthropic gateway (ADR-001).
#
# Usage:
#   bin/llm.sh MODEL [MAX_TOKENS] <<<'user prompt text'
#   echo "prompt" | bin/llm.sh claude-opus-4-8 4096
#   bin/llm.sh claude-opus-4-8 4096 --system "system text" <<<'user prompt'
#
# Prints the assistant's text to stdout. Token usage goes to stderr.
set -euo pipefail

GATEWAY="${LLM_GATEWAY:-http://169.254.169.254/gateway/llm/anthropic}/v1/messages"
MODEL="${1:?model id required}"; shift || true
MAX_TOKENS="${1:-4096}"; [[ "${1:-}" =~ ^[0-9]+$ ]] && shift || true
SYSTEM=""
if [[ "${1:-}" == "--system" ]]; then SYSTEM="$2"; shift 2; fi

PROMPT="$(cat)"

req="$(jq -n --arg m "$MODEL" --argjson mt "$MAX_TOKENS" \
        --arg sys "$SYSTEM" --arg p "$PROMPT" '
  {model:$m, max_tokens:$mt,
   messages:[{role:"user", content:$p}]}
  + (if $sys=="" then {} else {system:$sys} end)')"

resp="$(curl -sS "$GATEWAY" \
  -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
  -d "$req")"

if ! echo "$resp" | jq -e '.content' >/dev/null 2>&1; then
  echo "llm.sh: gateway error:" >&2
  echo "$resp" >&2
  exit 1
fi

echo "$resp" | jq -r '[.content[] | select(.type=="text") | .text] | join("")'
echo "$resp" | jq -c '{model, usage}' >&2
